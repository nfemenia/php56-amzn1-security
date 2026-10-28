Patched php56 packages for **Amazon Linux AMI 2018.03**, rebuilt from Amazon's `php56-5.6.40-1.144.amzn1` source RPM.

| File | Contents |
|---|---|
| `php56-amzn1-security-full.tar.gz` | **full**: all post-5.6.40 security fixes from deb.sury.org, incl. PHP2Shell |
| `php56-amzn1-security-min.tar.gz` | **min**: PHP2Shell fix (CVE-2026-109618, CVE-2026-109619) only |
| `php56-amzn1-security-5.6.40-*.tar.gz` | The same two tarballs under versioned names |
| `RPM-GPG-KEY` | Key the RPMs are signed with |
| `*.src.rpm` | Source RPMs |

```bash
curl -fLO https://github.com/nfemenia/php56-amzn1-security/releases/latest/download/php56-amzn1-security-full.tar.gz
tar xzf php56-amzn1-security-full.tar.gz && cd php56-amzn1-security-5.6.40-*/
sudo ./install.sh --dry-run
sudo ./install.sh
```

Or with yum, from the repositories at https://nfemenia.github.io/php56-amzn1-security/ ([how](../../blob/main/README.md#install-with-yum)).

Read [behaviour changes](../../blob/main/docs/behaviour-changes.md) before installing. Undo with `sudo ./rollback.sh`.
