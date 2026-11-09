"""Offline tests for unavailable networks, API throttling and safe inputs."""
import io
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
import urllib.error

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from check_upstream import download, extract, tag_key, Unavailable


class UpstreamTests(unittest.TestCase):
    def test_network_retries_are_bounded(self):
        calls, waits = [], []
        def unavailable(request, timeout):
            calls.append((request, timeout))
            raise urllib.error.URLError('offline')
        with self.assertRaisesRegex(Unavailable, 'three bounded attempts'):
            download('https://example.invalid', opener=unavailable, sleep=waits.append)
        self.assertEqual(len(calls), 3)
        self.assertEqual(waits, [1, 2])

    def test_rate_limit_does_not_retry_or_wait_for_reset(self):
        calls = []
        def limited(request, timeout):
            calls.append(request)
            raise urllib.error.HTTPError(request.full_url, 429, 'limited', {}, None)
        with self.assertRaisesRegex(Unavailable, 'rate-limited'):
            download('https://example.invalid', opener=limited, sleep=lambda _: self.fail('must not sleep'))
        self.assertEqual(len(calls), 1)

    def test_token_is_not_sent_to_archive_host(self):
        requests = []
        def respond(request, timeout):
            requests.append(request)
            return io.BytesIO(b'ok')
        download('https://api.github.com/repos/PowerShell/PSReadLine/tags', 'test-token', opener=respond)
        download('https://codeload.github.com/PowerShell/PSReadLine/tar.gz/sha', 'test-token', opener=respond)
        self.assertIsNotNone(requests[0].get_header('Authorization'))
        self.assertIsNone(requests[1].get_header('Authorization'))

    def test_tag_order(self):
        tags = ['v2.4.5', 'v2.5.0-beta1', 'v2.5.0', 'v2.4.10', 'unexpected']
        self.assertEqual(max(tags, key=tag_key), 'v2.5.0')
        self.assertGreater(tag_key('v2.5.0-beta10'), tag_key('v2.5.0-beta2'))

    def test_unsafe_archive_is_rejected_before_extraction(self):
        for name, kind in [('repo/../../escape', tarfile.REGTYPE), ('/escape', tarfile.REGTYPE), ('repo/link', tarfile.SYMTYPE)]:
            data = io.BytesIO()
            with tarfile.open(fileobj=data, mode='w:gz') as archive:
                good = tarfile.TarInfo('repo/good'); good.size = 2
                archive.addfile(good, io.BytesIO(b'ok'))
                bad = tarfile.TarInfo(name); bad.type = kind; bad.linkname = '/outside'
                archive.addfile(bad)
            with tempfile.TemporaryDirectory() as directory:
                target = Path(directory) / 'source'
                with self.assertRaisesRegex(ValueError, 'Unsafe'):
                    extract(data.getvalue(), target)
                self.assertFalse(target.exists())


if __name__ == '__main__':
    unittest.main()
