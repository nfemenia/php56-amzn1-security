Patched php56 packages for Amazon Linux AMI 2018.03
====================================================

Rebuilt from Amazon's own php56 source RPM with security fixes backported from
deb.sury.org's php5.6 packages. Full details, patch list and known behaviour
changes: https://github.com/OWNER/php56-amzn1-security

Install (only replaces the php56 5.6.40 packages already installed):

    sudo ./install.sh --dry-run        # show what would change
    sudo ./install.sh                  # back up, upgrade, pin, restart php-fpm
    sudo ./install.sh --check-url https://your-site/   # also check the site answers

Undo:

    sudo ./rollback.sh

Backups go to /root/php56-amzn1-security-backup-<timestamp>.

No warranty. Test on a staging server first.
