# Behaviour changes

Both variants include the PHP2Shell fix (CVE-2026-109618, CVE-2026-109619). It is a minimal
mitigation for an end-of-life branch, and it changes two things you may notice.

## Session upload progress is always off

`session.upload_progress.enabled` no longer does anything: upload progress tracking is disabled in
the code, whatever the ini setting says. `php -i` may still print `On`.

If your application reads `$_SESSION[ini_get('session.upload_progress.prefix') . ...]` to show upload
progress bars, those stay empty. Search for `upload_progress` in your code before installing.
Turning it off in the ini file (`session.upload_progress.enabled = Off`) was the recommended
workaround before the patch existed, so many servers already run this way.

PHP tests affected: `ext/session/tests/rfc1867*.phpt` (8 tests).

## Running out of memory ends the PHP process

When a script hits `memory_limit` (or a size-overflow error), PHP prints the usual fatal error and
then exits the process immediately (`_exit(1)`) instead of unwinding. As a result:

- register_shutdown_function() callbacks, destructors and output-buffer handlers do not run;
- the session is not written back for that request;
- under php-fpm the worker exits and the master starts a new one. The request still gets the
  error response; logs show `child NNN exited with code 1`.

Requests that stay under `memory_limit` are unaffected.

PHP test affected: `tests/lang/bug45392.phpt` (expects shutdown output after an out-of-memory error).

## `full` only

The extra fixes in the `full` variant make malformed input fail where 5.6.40 used to crash or
misbehave (mostly in exif, phar, mbstring, iconv, SOAP, mysqlnd and the cookie/multipart parsers).
Two tests added by those patches fail in this build for environmental reasons; see
`tests/expected-failures-full.txt`.
