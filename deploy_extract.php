<?php
@set_time_limit(300);
@ini_set('output_buffering', 'off');
@ob_end_flush();

if (($_GET['token'] ?? '') !== 'LN_DEPLOY_2026') {
    http_response_code(403);
    echo 'Unauthorized';
    exit;
}

$zipPath  = __DIR__ . '/learnova.zip';
$destPath = __DIR__ . '/';

if (!file_exists($zipPath)) {
    echo 'ZIP not found at: ' . $zipPath;
    exit;
}

// Try ZipArchive first
if (class_exists('ZipArchive')) {
    $zip = new ZipArchive;
    $res = $zip->open($zipPath);
    if ($res === TRUE) {
        $zip->extractTo($destPath);
        $zip->close();
        @unlink($zipPath);
        echo 'Deploy OK (ZipArchive) - ' . date('Y-m-d H:i:s');
    } else {
        echo 'ZipArchive open failed, code: ' . $res;
    }
} else {
    // Fallback: shell unzip
    $safeZip  = escapeshellarg($zipPath);
    $safeDest = escapeshellarg($destPath);
    exec("unzip -o $safeZip -d $safeDest 2>&1", $out, $ret);
    if ($ret === 0) {
        @unlink($zipPath);
        echo 'Deploy OK (unzip) - ' . date('Y-m-d H:i:s');
    } else {
        echo 'unzip failed (code ' . $ret . '): ' . implode(' | ', array_slice($out, -5));
    }
}
