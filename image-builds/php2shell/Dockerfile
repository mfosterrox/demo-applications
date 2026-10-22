# PHP2Shell lab image.
# Pins the 2026-10-19 ubi9/php-82 build (tag 1-1792440794).
# That image ships php-8.2.33-1.module+el9.8.0+24630+45254c6a.
# Red Hat catalog reports CVE-2026-109618 and CVE-2026-109619 on it.
# RHSA-2026:87072 fixes both in php-8.2.35. Floating tags :1 and :latest
# were rebuilt with 8.2.35 on 2026-10-22, so do not use them.
FROM registry.access.redhat.com/ubi9/php-82@sha256:f6800ac6fb904a48a90fdc319d008e3df4ac2122c91ffec6df4dcaaaecf800e8

LABEL org.opencontainers.image.title="PHP2Shell demo" \
      org.opencontainers.image.description="PHP 8.2.33 workload for RHACS detection of CVE-2026-109618 and CVE-2026-109619" \
      demo.cves="CVE-2026-109618,CVE-2026-109619" \
      demo.php-nevra="php-8.2.33-1.module+el9.8.0+24630+45254c6a" \
      demo.base-image="registry.access.redhat.com/ubi9/php-82:1-1792440794"

COPY index.php /tmp/src/index.php

USER 0
RUN /usr/libexec/s2i/assemble
USER 1001

EXPOSE 8080
CMD ["/usr/libexec/s2i/run"]
