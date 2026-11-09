using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Management.Automation;
using System.Management.Automation.Language;

namespace PowerShellCommandHighlighter
{
    // This type is compiled into the private PSReadLine build. No background runspace,
    // subprocess, key binding interception, terminal overlay or prompt hook is used.
    public sealed class CommandSpan
    {
        public int Start { get; internal set; }
        public int End { get; internal set; }
        public string Name { get; internal set; }
        public bool? Exists { get; internal set; }
        public string Color { get; internal set; }
    }

    public sealed class CommandExistenceHighlighter
    {
        public static bool Enabled { get; set; } = true;
        public const string ExistingColor = "\x1b[38;2;76;175;80m";
        public const string MissingColor = "\x1b[38;2;255;102;136m";
        public const int CacheMilliseconds = 250;
        private const int Capacity = 512;
        private readonly Dictionary<string, CacheEntry> cache =
            new Dictionary<string, CacheEntry>(StringComparer.OrdinalIgnoreCase);
        private readonly Dictionary<int, CommandSpan> spans = new Dictionary<int, CommandSpan>();
        private string path, pathExt, modulePath, location, autoloadPreference;
        private readonly List<EnvironmentChange> changes = new List<EnvironmentChange>();
        private readonly Dictionary<CommandSpan, CommandAst> commands = new Dictionary<CommandSpan, CommandAst>();

        private sealed class EnvironmentChange
        {
            public Ast Scope;
            public int Offset;
            public string Name;
            public bool SearchPath;
            public bool RemoveModule;
        }
        private Ast previousAst;
        private CommandSpan[] previousSpans;

        private struct CacheEntry
        {
            public long Time;
            public bool Exists;
            public bool SessionCommand;
            public string ModuleName;
        }

        // Called once at the start of every ReadLine, even when the engine instance
        // is unchanged. A function/alias/module/PATH change at the prompt is visible.
        public void Reset()
        {
            cache.Clear();
            spans.Clear();
            previousAst = null;
            previousSpans = null;
            changes.Clear();
            commands.Clear();
        }

        public CommandSpan[] Analyze(Ast ast, EngineIntrinsics engine)
        {
            spans.Clear();
            if (!Enabled || ast == null || engine == null) return new CommandSpan[0];
            var newPath = Environment.GetEnvironmentVariable("PATH");
            var newPathExt = Environment.GetEnvironmentVariable("PATHEXT");
            var newModulePath = Environment.GetEnvironmentVariable("PSModulePath");
            var newLocation = engine.SessionState.Path.CurrentLocation.Path;
            var newPreference = Convert.ToString(engine.SessionState.PSVariable.GetValue("PSModuleAutoLoadingPreference"));
            if (path != newPath || pathExt != newPathExt || modulePath != newModulePath || location != newLocation || autoloadPreference != newPreference)
            {
                cache.Clear();
                path = newPath;
                pathExt = newPathExt;
                modulePath = newModulePath;
                location = newLocation;
                autoloadPreference = newPreference;
            }

            // ParseInput owns the AST. Reuse command extents on cursor-only renders.
            if (!ReferenceEquals(previousAst, ast))
            {
                var found = new List<CommandSpan>();
                changes.Clear();
                commands.Clear();
                var nodes = new List<Ast>(ast.FindAll(a => a is FunctionDefinitionAst || a is CommandAst || a is AssignmentStatementAst, true));
                CollectChanges(nodes);
                foreach (var node in nodes)
                {
                    if (!(node is CommandAst command)) continue;
                    if (command.CommandElements.Count == 0) continue;
                    var first = command.CommandElements[0];
                    string name = null;
                    if (first is StringConstantExpressionAst literal) name = literal.Value;
                    else if (first is ExpandableStringExpressionAst expandable && expandable.NestedExpressions.Count == 0)
                        name = expandable.Value;
                    // Variables, scriptblocks, subexpressions, splatting etc. are not evaluated.
                    if (string.IsNullOrEmpty(name)) continue;
                    var span = new CommandSpan { Start = first.Extent.StartOffset, End = first.Extent.EndOffset, Name = name };
                    found.Add(span);
                    commands.Add(span, command);
                }
                previousAst = ast;
                previousSpans = found.ToArray();
            }

            var inThisRender = new Dictionary<string, bool?>(StringComparer.OrdinalIgnoreCase);
            foreach (var span in previousSpans)
            {
                bool? exists = null;
                if (!IsDirectlyChanged(span) && !inThisRender.TryGetValue(span.Name, out exists))
                {
                    exists = Resolve(span.Name, engine);
                    inThisRender.Add(span.Name, exists);
                }
                // A statement in the buffer has not run yet. Do not assume the
                // current session describes a name it may create/remove/rebind.
                bool? contextual = IsUncertain(span, exists) ? (bool?)null : exists;
                span.Exists = contextual;
                span.Color = contextual.HasValue ? (contextual.Value ? ExistingColor : MissingColor) : null;
                spans[span.Start] = span;
            }
            return previousSpans;
        }

        private static Ast ScopeOf(Ast node)
        {
            for (var parent = node.Parent; parent != null; parent = parent.Parent)
                if (parent is ScriptBlockAst)
                {
                    // Dot-sourced literal blocks share their caller's scope.
                    if (parent.Parent is ScriptBlockExpressionAst expression && expression.Parent is CommandAst invocation &&
                        invocation.InvocationOperator == TokenKind.Dot) continue;
                    return parent;
                }
            return null;
        }

        private static string Literal(Ast node)
        {
            if (node is StringConstantExpressionAst literal) return literal.Value;
            if (node is ExpandableStringExpressionAst expandable && expandable.NestedExpressions.Count == 0)
                return expandable.Value;
            return null;
        }

        private static string NameArgument(CommandAst command)
        {
            string positional = null;
            bool havePositional = false;
            for (int i = 1; i < command.CommandElements.Count; i++)
            {
                var element = command.CommandElements[i];
                if (element is CommandParameterAst parameter)
                {
                    if (parameter.ParameterName.Equals("Name", StringComparison.OrdinalIgnoreCase))
                        return Literal(parameter.Argument ?? (i + 1 < command.CommandElements.Count ? command.CommandElements[i + 1] : null));
                    // These are switches on the recognized alias commands.
                    if (parameter.Argument == null &&
                        !parameter.ParameterName.Equals("Force", StringComparison.OrdinalIgnoreCase) &&
                        !parameter.ParameterName.Equals("PassThru", StringComparison.OrdinalIgnoreCase)) i++;
                }
                else if (!havePositional)
                {
                    havePositional = true;
                    positional = Literal(element);
                }
            }
            return positional;
        }

        private void CollectChanges(IEnumerable<Ast> nodes)
        {
            foreach (var node in nodes)
            {
                if (node is FunctionDefinitionAst definition)
                {
                    // Scope qualifiers affect the same unqualified command name.
                    string name = definition.Name;
                    int colon = name.LastIndexOf(':');
                    changes.Add(new EnvironmentChange { Scope = ScopeOf(node), Offset = node.Extent.StartOffset,
                        Name = colon < 0 ? name : name.Substring(colon + 1) });
                }
                else if (node is AssignmentStatementAst assignment && assignment.Left is VariableExpressionAst variable)
                {
                    string name = variable.VariablePath.UserPath;
                    if (name.Equals("env:PATH", StringComparison.OrdinalIgnoreCase) ||
                        name.Equals("env:PATHEXT", StringComparison.OrdinalIgnoreCase) ||
                        name.Equals("env:PSModulePath", StringComparison.OrdinalIgnoreCase))
                        changes.Add(new EnvironmentChange { Scope = ScopeOf(node), Offset = node.Extent.EndOffset, SearchPath = true });
                }
                else if (node is CommandAst command && command.CommandElements.Count > 0)
                {
                    string name = Literal(command.CommandElements[0]);
                    if (name == null) continue;
                    if (command.InvocationOperator == TokenKind.Dot)
                        changes.Add(new EnvironmentChange { Scope = ScopeOf(node), Offset = node.Extent.EndOffset, SearchPath = true });
                    int slash = name.LastIndexOf('\\');
                    if (slash >= 0) name = name.Substring(slash + 1);
                    switch (name.ToLowerInvariant())
                    {
                        case "set-alias": case "new-alias": case "sal": case "nal":
                            changes.Add(new EnvironmentChange { Scope = ScopeOf(node), Offset = node.Extent.EndOffset, Name = NameArgument(command) });
                            break;
                        case "remove-module": case "rmo":
                            changes.Add(new EnvironmentChange { Scope = ScopeOf(node), Offset = node.Extent.EndOffset,
                                Name = NameArgument(command), RemoveModule = true });
                            break;
                        case "import-module": case "ipmo":
                        case "set-location": case "sl": case "cd": case "chdir":
                            changes.Add(new EnvironmentChange { Scope = ScopeOf(node), Offset = node.Extent.EndOffset, SearchPath = true });
                            break;
                    }
                }
            }
        }

        private bool Applies(EnvironmentChange change, CommandSpan span)
        {
            bool deferred = false;
            for (var parent = commands[span].Parent; parent != null; parent = parent.Parent)
            {
                if (parent is FunctionDefinitionAst) deferred = true;
                if (ReferenceEquals(parent, change.Scope)) return change.Offset <= span.Start || deferred;
            }
            return false;
        }

        private bool IsDirectlyChanged(CommandSpan span)
        {
            foreach (var change in changes)
                if (!change.SearchPath && !change.RemoveModule && Applies(change, span) &&
                    (change.Name != null && span.Name.Equals(change.Name, StringComparison.OrdinalIgnoreCase))) return true;
            return false;
        }

        private bool IsUncertain(CommandSpan span, bool? exists)
        {
            foreach (var change in changes)
            {
                if (!Applies(change, span)) continue;
                if (change.RemoveModule)
                {
                    if (cache.TryGetValue(span.Name, out var moduleEntry) && !string.IsNullOrEmpty(moduleEntry.ModuleName) &&
                        (change.Name == null || moduleEntry.ModuleName.Equals(change.Name, StringComparison.OrdinalIgnoreCase))) return true;
                    continue;
                }
                if (!change.SearchPath)
                {
                    if (change.Name == null ? exists != true : span.Name.Equals(change.Name, StringComparison.OrdinalIgnoreCase)) return true;
                }
                else
                {
                    // Preserve known session cmdlets/functions/aliases. Search-path
                    // dependent or currently missing commands need runtime state.
                    if (exists != true || span.Name.IndexOfAny(new[] { '/', '\\', ':' }) >= 0) return true;
                    if (!cache.TryGetValue(span.Name, out var entry) || !entry.SessionCommand) return true;
                }
            }
            return false;
        }

        private bool? Resolve(string name, EngineIntrinsics engine)
        {
            long now = Stopwatch.GetTimestamp();
            if (cache.TryGetValue(name, out var entry) &&
                (now - entry.Time) * 1000.0 / Stopwatch.Frequency < CacheMilliseconds)
                return entry.Exists;
            try
            {
                // The engine decides aliases, functions, autoloadable module commands,
                // external commands, explicit paths, extensions and script discovery.
                var info = engine.InvokeCommand.GetCommand(name, CommandTypes.All);
                bool exists = info != null;
                if (cache.Count >= Capacity) cache.Clear();
                cache[name] = new CacheEntry { Time = Stopwatch.GetTimestamp(), Exists = exists,
                    ModuleName = info?.ModuleName,
                    SessionCommand = info != null && (info.CommandType & (CommandTypes.Alias | CommandTypes.Function | CommandTypes.Filter | CommandTypes.Cmdlet)) != 0 };
                return exists;
            }
            catch (Exception e) when (!(e is OutOfMemoryException) && !(e is StackOverflowException))
            {
                // Discovery failures are unknown, not proof that a command is missing.
                return null;
            }
        }

        public string GetColor(Token token)
        {
            return spans.TryGetValue(token.Extent.StartOffset, out var span) && span.End == token.Extent.EndOffset
                ? span.Color : null;
        }
    }
}

namespace Microsoft.PowerShell
{
    public partial class PSConsoleReadLine
    {
        private readonly PowerShellCommandHighlighter.CommandExistenceHighlighter _commandHighlighter =
            new PowerShellCommandHighlighter.CommandExistenceHighlighter();

        public static void ClearCommandHighlighterCache() => _singleton._commandHighlighter.Reset();
    }
}
