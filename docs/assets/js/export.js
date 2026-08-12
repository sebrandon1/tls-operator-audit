function validateScanData(requireOperators) {
  if (!window.scanData) {
    alert('No scan data available');
    return null;
  }
  if (requireOperators && !window.scanData.operators) {
    alert('No operator data available');
    return null;
  }
  return window.scanData;
}

function downloadJSON(filename, data) {
  var blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
  downloadBlob(filename, blob);
}

function downloadCSV(filename, csvContent) {
  var blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
  downloadBlob(filename, blob);
}

function downloadBlob(filename, blob) {
  var link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = filename;
  link.style.display = 'none';
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(link.href);
}

function exportOperatorsJSON() {
  var data = validateScanData(false);
  if (!data) return;
  var filename = 'tls-operators-' + (data.scan_date || 'export') + '.json';
  downloadJSON(filename, data);
}

function exportOperatorsCSV() {
  var data = validateScanData(true);
  if (!data) return;

  var headers = ['Operator', 'Version', 'Jira', 'Project', 'Catalog', 'Total Endpoints', 'Reachable', 'Closed', 'ML-KEM', 'ML-KEM %', 'Status'];
  var rows = [headers.join(',')];

  data.operators.forEach(function(op) {
    var row = [
      csvEscape(op.name || ''),
      csvEscape(op.version || ''),
      csvEscape(op.jira || ''),
      csvEscape(op.project || ''),
      csvEscape(op.catalog || ''),
      op.total_endpoints || 0,
      op.reachable_endpoints || 0,
      op.closed_endpoints || 0,
      op.mlkem_endpoints || 0,
      op.mlkem_percent || 0,
      csvEscape(op.status || '')
    ];
    rows.push(row.join(','));
  });

  var filename = 'tls-operators-' + (data.scan_date || 'export') + '.csv';
  downloadCSV(filename, rows.join('\n'));
}

function exportOperatorJSON(operatorName) {
  var data = validateScanData(true);
  if (!data) return;

  var op = data.operators.find(function(o) { return o.name === operatorName; });
  if (!op) {
    alert('Operator not found: ' + operatorName);
    return;
  }

  var filename = 'tls-operator-' + operatorName + '-' + (data.scan_date || 'export') + '.json';
  downloadJSON(filename, op);
}

function exportOperatorCSV(operatorName) {
  var data = validateScanData(true);
  if (!data) return;

  var op = data.operators.find(function(o) { return o.name === operatorName; });
  if (!op || !op.endpoints) {
    alert('No endpoint data for operator: ' + operatorName);
    return;
  }

  var headers = ['Namespace', 'Host', 'Port', 'Status', 'Grade', 'TLS 1.2', 'TLS 1.3', 'Forward Secrecy', 'ML-KEM', 'PQC Readiness', 'Hostname Match', 'Cert Expiry Days'];
  var rows = [headers.join(',')];

  op.endpoints.forEach(function(ep) {
    var row = [
      csvEscape(ep.namespace || ''),
      csvEscape(ep.host || ''),
      ep.port || 0,
      csvEscape(ep.status || ''),
      csvEscape(ep.grade || ''),
      boolToYesNo(ep.tls12),
      boolToYesNo(ep.tls13),
      boolToYesNo(ep.forward_secrecy),
      boolToYesNo(ep.mlkem),
      csvEscape(ep.pqc_readiness || ''),
      boolToYesNo(ep.hostname_match),
      ep.cert_expiry_days !== undefined ? ep.cert_expiry_days : ''
    ];
    rows.push(row.join(','));
  });

  var filename = 'tls-operator-' + operatorName + '-endpoints-' + (data.scan_date || 'export') + '.csv';
  downloadCSV(filename, rows.join('\n'));
}

function csvEscape(str) {
  if (str === null || str === undefined) return '';
  str = String(str);
  if (str.indexOf(',') !== -1 || str.indexOf('"') !== -1 || str.indexOf('\n') !== -1) {
    if (str.indexOf('"') !== -1) {
      str = str.replace(/"/g, '""');
    }
    return '"' + str + '"';
  }
  return str;
}

function boolToYesNo(value) {
  return value ? 'Yes' : 'No';
}
