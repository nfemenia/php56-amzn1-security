# What is patched

Both variants start from Amazon's own source RPM, `php56-5.6.40-1.144.amzn1.src.rpm`, which already
carries Amazon's fixes (among them CVE-2019-11043 and CVE-2023-0662). Our patch is added after
Amazon's last one; nothing else in the spec changes.

## `min`: PHP2Shell only

[`patches/min/php2shell-CVE-2026-109618-109619.patch`](../patches/min/php2shell-CVE-2026-109618-109619.patch)
is deb.sury.org's `0261-Avoid-state-corruption-via-bailout.patch` byte for byte: Arnaud Le Blanc's
"minimal mitigation for EOL version" of CVE-2026-109618 and CVE-2026-109619. It applies to
Amazon's tree unchanged. See [behaviour-changes.md](behaviour-changes.md).

Both variants then apply [`patches/common/0265-php2shell-clear-freed-shutdown-state.patch`](../patches/common/0265-php2shell-clear-freed-shutdown-state.patch),
ours: three parts of the upstream fix ([php/php-src@712e60f9](https://github.com/php/php-src/commit/712e60f9edfd03f0960fc4fc3c2c375f42b90aa2))
that 0261 leaves out. At the end of each request PHP 5.6 frees the user error/exception handler
stacks and the autoload guard table but leaves the pointers set; the patch clears them, so an error
raised before the next request starts cannot reach freed memory. It also clears `$_GET`/`$_POST`/…
in `php_request_shutdown_for_hook()` (unused by the bundled SAPIs) and adds upstream's
`isspace((unsigned char)…)` cast. Added in `sec2`/`min2`.

## `full`: everything deb.sury.org fixed after 5.6.40

[`patches/full/series/`](../patches/full/series/) holds Ondřej Surý's patches **unmodified**, copied from
the php5.6 `5.6.40-105` Debian source package, in the order listed in
[`series`](../patches/full/series/series). They are applied with `git apply --exclude=NEWS`
(the `NEWS` file differs between the trees and is not packaged).

- 140 of Ondřej's patches 0056–0264, including 0261 (PHP2Shell).
- `../../common/0265-…`: the patch described under `min` above, applied last.
- `0260-openssl_encrypt-wrap-overflow-ported-to-amzn.patch`: Ondřej's 0260 does not apply to Amazon's
  `openssl.c`; this is the same fix placed by hand (both `outlen` calculations get the wrap-mode
  padding).

CVE IDs named in the included patches: CVE-2019-11034, -11035, -11038, -11039, -11040, -11041,
-11042, -11044, -11045, -11046, -11047, -11048, -11050, CVE-2019-13224, CVE-2020-7068,
CVE-2021-21702, CVE-2022-31629, CVE-2026-6735, CVE-2026-7261, CVE-2026-7262, CVE-2026-109618,
CVE-2026-109619. Many more patches fix memory-safety bugs ("Fix bug #NNNNN") in exif, phar, mbstring,
mysqlnd, SOAP, iconv, gd, bcmath, the upload/cookie parsers and the Zend engine without a CVE in
their header.

`build/regen-backports.sh` rebuilds `patches/full/backports.patch` (what the spec applies) and
`test-fixtures.tar.gz` (binary test files, which GNU patch on Amazon Linux 1 cannot apply) from the
series, so the shipped patch can be checked against the reviewed files.

### Not included

Patches 0001–0055 are Debian packaging changes that predate 5.6.40. Of 0056–0264, these are left out:

| Patches | Why |
|---|---|
| 0069 0097 0105 0126 0132 0139 0142 0154 0158 0168 0178 0184 0186 0188 0191 0198 0203 0206 0210 0212 0215 0220 0222 0225 0228 0233 0240 0256 | Only change `NEWS` |
| 0104, 0262 0263 0264 | CVE-2019-11043 and CVE-2023-0662: Amazon's spec already fixes them |
| 0087 | Test-only fixups |
| 0251 | Adds DNS-based usage telemetry to Debian's build; not a fix |
| 0070 0071 0072 0077 0081 0094 0127 0134 0152 0155 0156 0161 0162 0170 0193 0194 0195 0241–0250 0252 | Build-system and toolchain changes for newer Debian/Ubuntu (pkg-config, ICU, OpenSSL 3, autoconf, GCC, MSVC, LiteSpeed, readline); not needed with Amazon's toolchain |
| 0088 | Bundled SQLite upgrade; Amazon builds against the system SQLite |
| 0145 | aarch64 assembly; these packages are x86_64 only |
| 0164 | Adds MySQL 8's `utf8mb4_0900_*` collations to mysqlnd: a compatibility feature, not a fix |
| 0165 0166 0169 | Debian packaging credits in `phpinfo()` |
