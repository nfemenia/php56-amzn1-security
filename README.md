# php56-amzn1-security

Security-patched **php56** packages for **Amazon Linux AMI 2018.03** (Amazon Linux 1), for servers that
still run Amazon's `php56` RPMs and cannot move to a supported PHP or OS yet.

Amazon Linux 1 is end of life, and so is PHP 5.6. Nobody else ships fixes for this combination, but
Ondřej Surý keeps backporting security fixes into his php5.6 packages for Debian/Ubuntu
([deb.sury.org](https://deb.sury.org)), including the PHP2Shell fix (CVE-2026-109618, CVE-2026-109619).
This project applies those fixes to **Amazon's own source RPM** and ships ready-made RPMs: same
spec, same build options, same file layout and same config, plus the patches.

> **Use at your own risk.** This is a community backport, not an Amazon, PHP or Debian product.
> Test on a staging server first. Upgrading off PHP 5.6 is the real fix.

## Is this for me?

```bash
cat /etc/system-release            # Amazon Linux AMI release 2018.03
rpm -qa 'php56*' | grep 5.6.40     # php56-...-5.6.40-1.14x.amzn1
```

If both match, yes. x86_64 only.

## Two variants

| Variant | Release | Contents |
|---|---|---|
| **full** (recommended) | `5.6.40-1.144.sec1.amzn1` | 140 of deb.sury.org's post-5.6.40 security fixes, including PHP2Shell ([list](docs/patches.md)) |
| **min** | `5.6.40-1.144.min1.amzn1` | Only the PHP2Shell fix, for the smallest possible change |

Both change two behaviours: **session upload progress is always off**, and **a script that hits
`memory_limit` ends its process** without running shutdown functions. Read
[behaviour-changes.md](docs/behaviour-changes.md) before installing.

## Install

On the server, download the latest **full** build (use `min` instead of `full` for the PHP2Shell-only
variant) and check it:

```bash
cd /tmp
curl -fLO https://github.com/nfemenia/php56-amzn1-security/releases/latest/download/php56-amzn1-security-full.tar.gz
curl -fLO https://github.com/nfemenia/php56-amzn1-security/releases/latest/download/php56-amzn1-security-full.tar.gz.sha256
sha256sum -c php56-amzn1-security-full.tar.gz.sha256
```

Then install:

```bash
tar xzf php56-amzn1-security-full.tar.gz
cd php56-amzn1-security-5.6.40-*/
sudo ./install.sh --dry-run        # shows which packages change, changes nothing
sudo ./install.sh                  # or: sudo ./install.sh --check-url https://your-site/
```

Each [release](../../releases) also has the same tarballs under versioned names
(`php56-amzn1-security-5.6.40-1.144.sec1.tar.gz`), for pinning an exact version.

`install.sh`:

1. checks `SHA256SUMS` and the RPMs' GPG signature against the bundled `RPM-GPG-KEY`;
2. replaces **only the php56 5.6.40 packages already installed** (`php56-jsonc`, `php56-pecl-*` and
   anything else stay as they are, and nothing new is installed);
3. backs up `/etc/php*`, `/etc/php-fpm*`, `/etc/yum.repos.d`, the package list and the current Amazon
   RPMs to `/root/php56-amzn1-security-backup-<timestamp>`;
4. adds an `exclude=` for those packages to `amzn-main.repo` and `amzn-updates.repo`, so `yum update`
   never swaps them back for Amazon's unpatched build (`--no-pin` to skip);
5. checks PHP loads the same modules as before, then restarts php-fpm if it is running. With Apache
   and mod_php, restart httpd yourself.

Your ini files are not touched. Upgrading to a newer release of this project works the same way, and
rollback still returns to Amazon's packages. If the installed php56 packages are not Amazon's and were
not installed by `install.sh` (a build of your own, say), pass the Amazon RPMs to roll back to with
`--rollback-rpms DIR`.

To go back to Amazon's packages:

```bash
sudo ./rollback.sh                 # reinstalls the backed-up RPMs and removes the exclude
```

### Verifying where a download came from

On any machine with the [GitHub CLI](https://cli.github.com):

```bash
gh attestation verify php56-amzn1-security-full.tar.gz --repo nfemenia/php56-amzn1-security
```

The attestation proves the tarball was built by this repository's
[workflow](.github/workflows/build.yml) from the tagged commit, not uploaded by hand.

## How it is built

[`build/build.sh`](build/build.sh) runs in a throwaway `amazonlinux:2018.03` container:

1. downloads `php56-5.6.40-1.144.amzn1.src.rpm` from Amazon's repository;
2. adds one patch after Amazon's last (`Patch10003`) and appends `.sec1`/`.min1` to the release;
3. builds with `rpmbuild` exactly as Amazon's spec does;
4. runs PHP's test suite (about 13,900 tests) and fails if anything fails that is not listed in
   [`tests/expected-failures-*.txt`](tests/), each entry with its reason.

Build it yourself (about 30 minutes, 3 GB RAM):

```bash
build/docker-build.sh full          # RPMs and test results in out/full/
```

## Test results

| Build | Failed tests (of 13,894) | Difference |
|---|---|---|
| Amazon 1.144, unpatched | 32 | Environment: newer tzdata, expired test certificates, running as root |
| min | 41 | +9 from the two behaviour changes above |
| full | 43 | +9, plus 2 tests added by the backports ([why](tests/expected-failures-full.txt)) |

No test that passes on Amazon's build fails on ours for any other reason.

## Maintainers: releasing

1. Create an RSA signing key once (Amazon Linux 1's rpm cannot verify EdDSA keys) and store the
   armored private key as the `RPM_SIGNING_KEY` secret (and `RPM_SIGNING_PASSPHRASE` if it has one):
   ```bash
   gpg --quick-generate-key "php56-amzn1-security <you@example.com>" rsa4096 sign 5y
   gpg --armor --export-secret-keys <KEYID> | gh secret set RPM_SIGNING_KEY
   ```
2. Push a tag: `git tag v5.6.40-1.144.sec1 && git push --tags`. The [workflow](.github/workflows/build.yml)
   builds both variants, runs the tests, signs, packages, attests and publishes the release.

When deb.sury.org ships new fixes: add the patches to `patches/full/series/` and its `series` file,
run `build/regen-backports.sh`, bump `FULL_SUFFIX` in [`build/versions.env`](build/versions.env)
(`sec1` → `sec2`) and tag.

## Credits and license

The patches are by the PHP developers, backported by **Ondřej Surý** (deb.sury.org); the PHP2Shell
mitigation for 5.6 is by **Arnaud Le Blanc**. They are under the [PHP License 3.01](https://www.php.net/license/3_01.txt),
as is PHP itself. The build is Amazon's php56 spec. This repository's scripts are MIT licensed
([LICENSE](LICENSE)).

Not affiliated with or endorsed by Amazon Web Services, The PHP Group or Debian.
