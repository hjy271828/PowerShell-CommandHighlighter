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
        private string path, pathExt, modulePath, location;
        private Ast previousAst;
        private CommandSpan[] previousSpans;

        private struct CacheEntry
        {
            public long Time;
            public bool Exists;
        }

        // Called once at the start of every ReadLine, even when the engine instance
        // is unchanged. A function/alias/module/PATH change at the prompt is visible.
        public void Reset()
        {
            cache.Clear();
            spans.Clear();
            previousAst = null;
            previousSpans = null;
        }

        public CommandSpan[] Analyze(Ast ast, EngineIntrinsics engine)
        {
            spans.Clear();
            if (!Enabled || ast == null || engine == null) return new CommandSpan[0];
            var newPath = Environment.GetEnvironmentVariable("PATH");
            var newPathExt = Environment.GetEnvironmentVariable("PATHEXT");
            var newModulePath = Environment.GetEnvironmentVariable("PSModulePath");
            var newLocation = engine.SessionState.Path.CurrentLocation.Path;
            if (path != newPath || pathExt != newPathExt || modulePath != newModulePath || location != newLocation)
            {
                cache.Clear();
                path = newPath;
                pathExt = newPathExt;
                modulePath = newModulePath;
                location = newLocation;
            }

            // ParseInput owns the AST. Reuse command extents on cursor-only renders.
            if (!ReferenceEquals(previousAst, ast))
            {
                var found = new List<CommandSpan>();
                foreach (var node in ast.FindAll(a => a is CommandAst, searchNestedScriptBlocks: true))
                {
                    var command = (CommandAst)node;
                    if (command.CommandElements.Count == 0) continue;
                    var first = command.CommandElements[0];
                    string name = null;
                    if (first is StringConstantExpressionAst literal) name = literal.Value;
                    else if (first is ExpandableStringExpressionAst expandable && expandable.NestedExpressions.Count == 0)
                        name = expandable.Value;
                    // Variables, scriptblocks, subexpressions, splatting etc. are not evaluated.
                    if (string.IsNullOrEmpty(name)) continue;
                    found.Add(new CommandSpan { Start = first.Extent.StartOffset, End = first.Extent.EndOffset, Name = name });
                }
                previousAst = ast;
                previousSpans = found.ToArray();
            }

            var inThisRender = new Dictionary<string, bool?>(StringComparer.OrdinalIgnoreCase);
            foreach (var span in previousSpans)
            {
                if (!inThisRender.TryGetValue(span.Name, out var exists))
                {
                    exists = Resolve(span.Name, engine);
                    inThisRender.Add(span.Name, exists);
                }
                span.Exists = exists;
                span.Color = exists.HasValue ? (exists.Value ? ExistingColor : MissingColor) : null;
                spans[span.Start] = span;
            }
            return previousSpans;
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
                bool exists = engine.InvokeCommand.GetCommand(name, CommandTypes.All) != null;
                if (cache.Count >= Capacity) cache.Clear();
                cache[name] = new CacheEntry { Time = Stopwatch.GetTimestamp(), Exists = exists };
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
