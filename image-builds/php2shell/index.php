<?php
http_response_code(200);
header('Content-Type: text/html; charset=utf-8');
$version = htmlspecialchars(PHP_VERSION, ENT_QUOTES, 'UTF-8');
$sapi = htmlspecialchars(PHP_SAPI, ENT_QUOTES, 'UTF-8');
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>PHP2Shell demo</title>
</head>
<body>
  <h1>PHP2Shell demo</h1>
  <p>This workload runs the PHP packages from the 2026-10-19 Red Hat ubi9/php-82 image. Image scanners report both CVEs from those packages.</p>
  <ul>
    <li>PHP version: <?php echo $version; ?></li>
    <li>SAPI: <?php echo $sapi; ?></li>
    <li>Package: php-8.2.33-1.module+el9.8.0+24630+45254c6a</li>
    <li>CVEs: CVE-2026-109618, CVE-2026-109619</li>
  </ul>
  <p>Rebuild on php-8.2.35 or newer (RHSA-2026:87072) and restart the PHP workers to clear both CVEs.</p>
</body>
</html>
