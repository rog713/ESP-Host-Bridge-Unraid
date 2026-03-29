<?php
$pluginName = 'esp-host-bridge';
$stateDir = "/boot/config/plugins/{$pluginName}";
$pluginCfg = "{$stateDir}/plugin.cfg";
$logFile = '/boot/logs/esp_host_bridge_webui.log';
$serviceScript = '/etc/rc.d/rc.esp_host_bridge';
$pluginVersionFile = "/usr/local/emhttp/plugins/{$pluginName}/plugin.version";
$defaults = array(
    'HM_PORT' => '8654',
    'HM_BIND_HOST' => '0.0.0.0',
    'HM_AUTOSTART' => 'yes',
);

function hm_json($status, $payload) {
    http_response_code((int)$status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($payload, JSON_UNESCAPED_SLASHES);
    exit;
}

function hm_load_cfg($path, $defaults) {
    $cfg = $defaults;
    if (!is_file($path)) {
        return $cfg;
    }
    $lines = @file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    if (!is_array($lines)) {
        return $cfg;
    }
    foreach ($lines as $line) {
        if ($line === '' || $line[0] === '#') {
            continue;
        }
        $parts = explode('=', $line, 2);
        if (count($parts) !== 2) {
            continue;
        }
        $key = trim($parts[0]);
        $value = trim($parts[1]);
        $cfg[$key] = trim($value, "\"'");
    }
    if (!preg_match('/^\d{1,5}$/', isset($cfg['HM_PORT']) ? (string)$cfg['HM_PORT'] : '')) {
        $cfg['HM_PORT'] = $defaults['HM_PORT'];
    }
    $port = (int)$cfg['HM_PORT'];
    if ($port < 1 || $port > 65535) {
        $cfg['HM_PORT'] = $defaults['HM_PORT'];
    }
    if (!isset($cfg['HM_BIND_HOST']) || $cfg['HM_BIND_HOST'] === '') {
        $cfg['HM_BIND_HOST'] = $defaults['HM_BIND_HOST'];
    }
    if (!isset($cfg['HM_AUTOSTART']) || $cfg['HM_AUTOSTART'] === '') {
        $cfg['HM_AUTOSTART'] = $defaults['HM_AUTOSTART'];
    }
    return $cfg;
}

function hm_save_cfg($path, $cfg, $defaults) {
    $stateDir = dirname($path);
    if (!is_dir($stateDir) && !@mkdir($stateDir, 0777, true) && !is_dir($stateDir)) {
        return false;
    }
    $port = isset($cfg['HM_PORT']) ? (string)$cfg['HM_PORT'] : $defaults['HM_PORT'];
    if (!preg_match('/^\d{1,5}$/', $port) || (int)$port < 1 || (int)$port > 65535) {
        $port = $defaults['HM_PORT'];
    }
    $bindHost = trim(isset($cfg['HM_BIND_HOST']) ? (string)$cfg['HM_BIND_HOST'] : $defaults['HM_BIND_HOST']);
    if ($bindHost === '') {
        $bindHost = $defaults['HM_BIND_HOST'];
    }
    $autostart = strtolower(isset($cfg['HM_AUTOSTART']) ? (string)$cfg['HM_AUTOSTART'] : $defaults['HM_AUTOSTART']);
    $autostart = in_array($autostart, array('1', 'true', 'yes', 'on'), true) ? 'yes' : 'no';
    $body = "HM_PORT=\"{$port}\"\nHM_BIND_HOST=\"{$bindHost}\"\nHM_AUTOSTART=\"{$autostart}\"\n";
    return @file_put_contents($path, $body) !== false;
}

function hm_exec($command) {
    $lines = array();
    $rc = 0;
    exec($command . ' 2>&1', $lines, $rc);
    return array('rc' => $rc, 'output' => implode("\n", $lines));
}

function hm_bridge_status($port) {
    $url = "http://127.0.0.1:{$port}/api/status";
    $body = null;
    $code = 0;
    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        curl_setopt_array($ch, array(
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 2,
            CURLOPT_CONNECTTIMEOUT => 1,
            CURLOPT_FAILONERROR => false,
        ));
        $body = curl_exec($ch);
        if (is_string($body)) {
            $code = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        }
        curl_close($ch);
    } else {
        $ctx = stream_context_create(array(
            'http' => array('timeout' => 2, 'ignore_errors' => true),
        ));
        $body = @file_get_contents($url, false, $ctx);
        if (isset($http_response_header) && is_array($http_response_header) && preg_match('/\s(\d{3})\s/', $http_response_header[0], $m)) {
            $code = (int)$m[1];
        }
    }
    if (!is_string($body) || $body === '') {
        return null;
    }
    $json = json_decode($body, true);
    if (!is_array($json)) {
        return null;
    }
    $json['_http_code'] = $code;
    return $json;
}

function hm_tail_log($path, $lines) {
    if (!is_file($path)) {
        return "No log file yet.\n";
    }
    $content = @file($path, FILE_IGNORE_NEW_LINES);
    if (!is_array($content) || $content === array()) {
        return "Log file is empty.\n";
    }
    $tail = array_slice($content, -1 * max(1, (int)$lines));
    return implode("\n", $tail) . "\n";
}

function hm_plugin_version($path) {
    if (!is_file($path)) {
        return '';
    }
    $raw = @file_get_contents($path);
    if (!is_string($raw)) {
        return '';
    }
    return trim($raw);
}

function hm_webui_host() {
    $host = isset($_SERVER['HTTP_HOST']) ? (string)$_SERVER['HTTP_HOST'] : '';
    if ($host !== '') {
        $parts = explode(':', $host, 2);
        if ($parts[0] !== '') {
            return $parts[0];
        }
    }
    $server = isset($_SERVER['SERVER_NAME']) ? (string)$_SERVER['SERVER_NAME'] : '';
    return $server !== '' ? $server : 'tower';
}

$cfg = hm_load_cfg($pluginCfg, $defaults);
$action = isset($_REQUEST['action']) ? $_REQUEST['action'] : 'status';

switch ($action) {
    case 'status':
        $svc = hm_exec(escapeshellcmd($serviceScript) . ' status');
        $bridge = hm_bridge_status((int)$cfg['HM_PORT']);
        $pluginVersion = hm_plugin_version($pluginVersionFile);
        hm_json(200, array(
            'ok' => true,
            'service' => array(
                'running' => $svc['rc'] === 0,
                'message' => trim($svc['output']),
            ),
            'plugin' => array_merge($cfg, array(
                'enabled' => strtolower(isset($cfg['HM_AUTOSTART']) ? (string)$cfg['HM_AUTOSTART'] : 'yes') === 'yes',
                'version' => $pluginVersion,
            )),
            'paths' => array(
                'plugin_cfg' => $pluginCfg,
                'webui_cfg' => "{$stateDir}/config.json",
                'deps_dir' => "/usr/local/emhttp/plugins/{$pluginName}/vendor",
                'log_file' => $logFile,
                'plugin_version' => $pluginVersionFile,
            ),
            'webui_url' => 'http://' . hm_webui_host() . ':' . $cfg['HM_PORT'] . '/',
            'bridge' => $bridge,
        ));
        break;

    case 'tail_log':
        $lines = isset($_GET['lines']) ? (int)$_GET['lines'] : 120;
        hm_json(200, array('ok' => true, 'log' => hm_tail_log($logFile, min(max($lines, 1), 400))));
        break;

    case 'save':
        $next = array(
            'HM_PORT' => isset($_POST['port']) ? (string)$_POST['port'] : $cfg['HM_PORT'],
            'HM_BIND_HOST' => isset($_POST['bind_host']) ? (string)$_POST['bind_host'] : $cfg['HM_BIND_HOST'],
            'HM_AUTOSTART' => isset($_POST['autostart']) ? 'yes' : 'no',
        );
        if (!hm_save_cfg($pluginCfg, $next, $defaults)) {
            hm_json(500, array('ok' => false, 'message' => 'Failed to save plugin config'));
        }
        hm_json(200, array('ok' => true, 'message' => 'Saved plugin settings', 'plugin' => hm_load_cfg($pluginCfg, $defaults)));
        break;

    case 'enable':
    case 'disable':
        $next = $cfg;
        $next['HM_AUTOSTART'] = $action === 'enable' ? 'yes' : 'no';
        if (!hm_save_cfg($pluginCfg, $next, $defaults)) {
            hm_json(500, array('ok' => false, 'message' => 'Failed to save plugin config'));
        }
        if ($action === 'disable') {
            $svc = hm_exec(escapeshellcmd($serviceScript) . ' stop');
            hm_json($svc['rc'] === 0 ? 200 : 500, array('ok' => $svc['rc'] === 0, 'message' => trim($svc['output']) !== '' ? trim($svc['output']) : 'Plugin disabled'));
        }
        hm_json(200, array('ok' => true, 'message' => 'Plugin enabled'));
        break;

    case 'start':
    case 'stop':
    case 'restart':
        $svc = hm_exec(escapeshellcmd($serviceScript) . ' ' . escapeshellarg($action));
        hm_json($svc['rc'] === 0 ? 200 : 500, array('ok' => $svc['rc'] === 0, 'message' => trim($svc['output'])));
        break;

    default:
        hm_json(400, array('ok' => false, 'message' => 'Unsupported action'));
}
