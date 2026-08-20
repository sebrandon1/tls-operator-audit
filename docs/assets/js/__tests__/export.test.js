/**
 * @jest-environment jsdom
 */

const fs = require('fs');
const path = require('path');

const exportJs = fs.readFileSync(
  path.join(__dirname, '../export.js'),
  'utf8'
);

// Note: Using eval() here is acceptable for test-only code with controlled input
// eslint-disable-next-line no-eval
eval(exportJs);

const originalDownloadBlob = downloadBlob;
const originalDownloadJSON = downloadJSON;
const originalDownloadCSV = downloadCSV;

function restoreExportFns() {
  downloadBlob = originalDownloadBlob;
  downloadJSON = originalDownloadJSON;
  downloadCSV = originalDownloadCSV;
}

afterEach(() => {
  restoreExportFns();
});

describe('csvEscape', () => {
  test('returns empty string for null', () => {
    expect(csvEscape(null)).toBe('');
  });

  test('returns empty string for undefined', () => {
    expect(csvEscape(undefined)).toBe('');
  });

  test('returns string as-is when no special characters', () => {
    expect(csvEscape('simple')).toBe('simple');
    expect(csvEscape('test123')).toBe('test123');
  });

  test('wraps and escapes string with comma', () => {
    expect(csvEscape('hello,world')).toBe('"hello,world"');
  });

  test('wraps and escapes string with quotes', () => {
    expect(csvEscape('say "hello"')).toBe('"say ""hello"""');
  });

  test('wraps string with newline', () => {
    expect(csvEscape('line1\nline2')).toBe('"line1\nline2"');
  });

  test('handles multiple special characters', () => {
    expect(csvEscape('test,"value",\nnew')).toBe('"test,""value"",\nnew"');
  });

  test('converts non-string values to string', () => {
    expect(csvEscape(123)).toBe('123');
    expect(csvEscape(true)).toBe('true');
  });

  test('optimizes by not replacing quotes when none present', () => {
    expect(csvEscape('hello,world')).toBe('"hello,world"');
  });
});

describe('boolToYesNo', () => {
  test('returns Yes for true', () => {
    expect(boolToYesNo(true)).toBe('Yes');
  });

  test('returns No for false', () => {
    expect(boolToYesNo(false)).toBe('No');
  });

  test('returns No for falsy values', () => {
    expect(boolToYesNo(null)).toBe('No');
    expect(boolToYesNo(undefined)).toBe('No');
    expect(boolToYesNo(0)).toBe('No');
  });
});

describe('validateScanData', () => {
  let mockAlert;

  beforeEach(() => {
    mockAlert = jest.fn();
    global.alert = mockAlert;
    window.scanData = null;
  });

  test('returns null and alerts when no scan data', () => {
    const result = validateScanData(false);
    expect(result).toBeNull();
    expect(mockAlert).toHaveBeenCalledWith('No scan data available');
  });

  test('returns data when scan data exists and operators not required', () => {
    window.scanData = { test: 'data' };
    const result = validateScanData(false);
    expect(result).toEqual({ test: 'data' });
    expect(mockAlert).not.toHaveBeenCalled();
  });

  test('returns null and alerts when operators required but missing', () => {
    window.scanData = { test: 'data' };
    const result = validateScanData(true);
    expect(result).toBeNull();
    expect(mockAlert).toHaveBeenCalledWith('No operator data available');
  });

  test('returns data when operators required and present', () => {
    window.scanData = { operators: [] };
    const result = validateScanData(true);
    expect(result).toEqual({ operators: [] });
    expect(mockAlert).not.toHaveBeenCalled();
  });
});

describe('downloadBlob', () => {
  let originalCreateElement;
  let originalCreateObjectURL;
  let originalRevokeObjectURL;
  let mockLink;

  beforeEach(() => {
    mockLink = {
      href: '',
      download: '',
      style: { display: '' },
      click: jest.fn(),
    };

    originalCreateElement = document.createElement;
    document.createElement = jest.fn(() => mockLink);

    document.body.appendChild = jest.fn();
    document.body.removeChild = jest.fn();

    originalCreateObjectURL = URL.createObjectURL;
    URL.createObjectURL = jest.fn(() => 'blob:mock-url');

    originalRevokeObjectURL = URL.revokeObjectURL;
    URL.revokeObjectURL = jest.fn();
  });

  afterEach(() => {
    document.createElement = originalCreateElement;
    URL.createObjectURL = originalCreateObjectURL;
    URL.revokeObjectURL = originalRevokeObjectURL;
  });

  test('creates blob URL and triggers download', () => {
    const blob = new Blob(['test'], { type: 'text/plain' });
    downloadBlob('test.txt', blob);

    expect(URL.createObjectURL).toHaveBeenCalledWith(blob);
    expect(mockLink.href).toBe('blob:mock-url');
    expect(mockLink.download).toBe('test.txt');
    expect(mockLink.style.display).toBe('none');
    expect(mockLink.click).toHaveBeenCalled();
    expect(document.body.appendChild).toHaveBeenCalledWith(mockLink);
    expect(document.body.removeChild).toHaveBeenCalledWith(mockLink);
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:mock-url');
  });
});

describe('downloadJSON', () => {
  let mockDownloadBlob;

  beforeEach(() => {
    mockDownloadBlob = jest.fn();
    downloadBlob = mockDownloadBlob;
  });

  test('creates JSON blob with formatted content', () => {
    const data = { key: 'value', num: 123 };
    downloadJSON('test.json', data);

    expect(mockDownloadBlob).toHaveBeenCalledWith(
      'test.json',
      expect.any(Blob)
    );

    const blob = mockDownloadBlob.mock.calls[0][1];
    expect(blob.type).toBe('application/json');
  });

  test('formats JSON with 2-space indentation', async () => {
    const data = { nested: { key: 'value' } };
    downloadJSON('test.json', data);

    const blob = mockDownloadBlob.mock.calls[0][1];
    const text = await new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.onerror = reject;
      reader.readAsText(blob);
    });
    expect(text).toBe(JSON.stringify(data, null, 2));
  });
});

describe('downloadCSV', () => {
  let mockDownloadBlob;

  beforeEach(() => {
    mockDownloadBlob = jest.fn();
    downloadBlob = mockDownloadBlob;
  });

  test('creates CSV blob with correct content type', () => {
    const csv = 'header1,header2\nval1,val2';
    downloadCSV('test.csv', csv);

    expect(mockDownloadBlob).toHaveBeenCalledWith(
      'test.csv',
      expect.any(Blob)
    );

    const blob = mockDownloadBlob.mock.calls[0][1];
    expect(blob.type).toBe('text/csv;charset=utf-8;');
  });
});

describe('exportOperatorsJSON', () => {
  let mockDownloadJSON;
  let mockAlert;

  beforeEach(() => {
    mockDownloadJSON = jest.fn();
    downloadJSON = mockDownloadJSON;
    mockAlert = jest.fn();
    global.alert = mockAlert;
  });

  test('alerts when no scan data available', () => {
    window.scanData = null;
    exportOperatorsJSON();

    expect(mockAlert).toHaveBeenCalledWith('No scan data available');
    expect(mockDownloadJSON).not.toHaveBeenCalled();
  });

  test('downloads full scan data with scan_date in filename', () => {
    window.scanData = {
      scan_date: '2024-01-15',
      operators: [],
      summary: {},
    };
    exportOperatorsJSON();

    expect(mockDownloadJSON).toHaveBeenCalledWith(
      'tls-operators-2024-01-15.json',
      window.scanData
    );
  });

  test('uses "export" when scan_date is missing', () => {
    window.scanData = { operators: [] };
    exportOperatorsJSON();

    expect(mockDownloadJSON).toHaveBeenCalledWith(
      'tls-operators-export.json',
      window.scanData
    );
  });
});

describe('exportOperatorsCSV', () => {
  let mockDownloadCSV;
  let mockAlert;

  beforeEach(() => {
    mockDownloadCSV = jest.fn();
    downloadCSV = mockDownloadCSV;
    mockAlert = jest.fn();
    global.alert = mockAlert;
  });

  test('alerts when no scan data available', () => {
    window.scanData = null;
    exportOperatorsCSV();

    expect(mockAlert).toHaveBeenCalledWith('No scan data available');
    expect(mockDownloadCSV).not.toHaveBeenCalled();
  });

  test('exports operators with correct CSV format', () => {
    window.scanData = {
      scan_date: '2024-01-15',
      operators: [
        {
          name: 'test-operator',
          version: '1.0.0',
          jira: 'TEST-123',
          project: 'TestProject',
          catalog: 'redhat-operators',
          total_endpoints: 10,
          reachable_endpoints: 8,
          closed_endpoints: 2,
          mlkem_endpoints: 5,
          mlkem_percent: 62.5,
          status: 'PARTIAL',
        },
      ],
    };

    exportOperatorsCSV();

    expect(mockDownloadCSV).toHaveBeenCalledWith(
      'tls-operators-2024-01-15.csv',
      expect.stringContaining('Operator,Version,Jira,Project,Catalog')
    );

    const csv = mockDownloadCSV.mock.calls[0][1];
    expect(csv).toContain('test-operator,1.0.0,TEST-123,TestProject');
    expect(csv).toContain('10,8,2,5,62.5,PARTIAL');
  });

  test('handles missing fields with empty strings or zeros', () => {
    window.scanData = {
      operators: [
        {
          name: 'minimal-op',
        },
      ],
    };

    exportOperatorsCSV();

    const csv = mockDownloadCSV.mock.calls[0][1];
    expect(csv).toContain('minimal-op,,,,,0,0,0,0,0,');
  });

  test('escapes CSV special characters in operator fields', () => {
    window.scanData = {
      operators: [
        {
          name: 'operator,with,commas',
          version: '1.0',
          jira: 'TEST-1',
          project: 'Project "quoted"',
          catalog: 'test',
          total_endpoints: 1,
          reachable_endpoints: 1,
          closed_endpoints: 0,
          mlkem_endpoints: 0,
          mlkem_percent: 0,
          status: 'FAIL',
        },
      ],
    };

    exportOperatorsCSV();

    const csv = mockDownloadCSV.mock.calls[0][1];
    expect(csv).toContain('"operator,with,commas"');
    expect(csv).toContain('"Project ""quoted"""');
  });
});

describe('exportOperatorJSON', () => {
  let mockDownloadJSON;
  let mockAlert;

  beforeEach(() => {
    mockDownloadJSON = jest.fn();
    downloadJSON = mockDownloadJSON;
    mockAlert = jest.fn();
    global.alert = mockAlert;
  });

  test('alerts when no scan data available', () => {
    window.scanData = null;
    exportOperatorJSON('test-op');

    expect(mockAlert).toHaveBeenCalledWith('No scan data available');
    expect(mockDownloadJSON).not.toHaveBeenCalled();
  });

  test('alerts when operator not found', () => {
    window.scanData = {
      operators: [{ name: 'other-op' }],
    };
    exportOperatorJSON('test-op');

    expect(mockAlert).toHaveBeenCalledWith('Operator not found: test-op');
    expect(mockDownloadJSON).not.toHaveBeenCalled();
  });

  test('downloads specific operator data', () => {
    const testOp = {
      name: 'test-operator',
      version: '1.0.0',
      endpoints: [],
    };

    window.scanData = {
      scan_date: '2024-01-15',
      operators: [testOp, { name: 'other-op' }],
    };

    exportOperatorJSON('test-operator');

    expect(mockDownloadJSON).toHaveBeenCalledWith(
      'tls-operator-test-operator-2024-01-15.json',
      testOp
    );
  });
});

describe('exportOperatorCSV', () => {
  let mockDownloadCSV;
  let mockAlert;

  beforeEach(() => {
    mockDownloadCSV = jest.fn();
    downloadCSV = mockDownloadCSV;
    mockAlert = jest.fn();
    global.alert = mockAlert;
  });

  test('alerts when no endpoint data available', () => {
    window.scanData = {
      operators: [{ name: 'test-op' }],
    };
    exportOperatorCSV('test-op');

    expect(mockAlert).toHaveBeenCalledWith(
      'No endpoint data for operator: test-op'
    );
    expect(mockDownloadCSV).not.toHaveBeenCalled();
  });

  test('exports endpoint data with boolean fields as Yes/No', () => {
    window.scanData = {
      scan_date: '2024-01-15',
      operators: [
        {
          name: 'test-operator',
          endpoints: [
            {
              namespace: 'test-ns',
              host: 'test.example.com',
              port: 443,
              status: 'Compliant',
              grade: 'A',
              tls12: true,
              tls13: false,
              forward_secrecy: true,
              mlkem: false,
              pqc_readiness: 'NotReady',
              hostname_match: true,
              cert_expiry_days: 90,
            },
          ],
        },
      ],
    };

    exportOperatorCSV('test-operator');

    expect(mockDownloadCSV).toHaveBeenCalledWith(
      'tls-operator-test-operator-endpoints-2024-01-15.csv',
      expect.stringContaining('Namespace,Host,Port,Status,Grade')
    );

    const csv = mockDownloadCSV.mock.calls[0][1];
    expect(csv).toContain('test-ns,test.example.com,443,Compliant,A');
    expect(csv).toContain('Yes,No,Yes,No,NotReady,Yes,90');
  });

  test('handles missing endpoint fields gracefully', () => {
    window.scanData = {
      operators: [
        {
          name: 'test-operator',
          endpoints: [
            {
              host: 'minimal.example.com',
              port: 8080,
            },
          ],
        },
      ],
    };

    exportOperatorCSV('test-operator');

    const csv = mockDownloadCSV.mock.calls[0][1];
    expect(csv).toContain(',minimal.example.com,8080,,,No,No,No,No,,No,');
  });

  test('escapes CSV special characters in endpoint fields', () => {
    window.scanData = {
      operators: [
        {
          name: 'test-operator',
          endpoints: [
            {
              namespace: 'ns,with,commas',
              host: 'host-with-"quotes".com',
              port: 443,
              status: 'Compliant',
              grade: 'A',
              tls12: false,
              tls13: false,
              forward_secrecy: false,
              mlkem: false,
              pqc_readiness: 'Ready',
              hostname_match: false,
            },
          ],
        },
      ],
    };

    exportOperatorCSV('test-operator');

    const csv = mockDownloadCSV.mock.calls[0][1];
    expect(csv).toContain('"ns,with,commas"');
    expect(csv).toContain('"host-with-""quotes"".com"');
  });
});

describe('formatWorkload', () => {
  test('returns empty string when workload is missing', () => {
    expect(formatWorkload({})).toBe('');
    expect(formatWorkload({ workload: { pods: [] } })).toBe('');
    expect(formatWorkload(null)).toBe('');
  });

  test('formats pod/container:image:tag@digest', () => {
    const result = formatWorkload({
      workload: {
        pods: [
          {
            name: 'manager-xyz',
            containers: [
              {
                name: 'manager',
                image: 'quay.io/org/app',
                tag: 'v2.0',
                digest: 'sha256:abc',
              },
              {
                name: 'kube-rbac-proxy',
                image: 'registry.redhat.io/openshift4/ose-kube-rbac-proxy',
                tag: 'v4.18',
                digest: 'sha256:def',
              },
            ],
          },
        ],
      },
    });

    expect(result).toBe(
      'manager-xyz/manager:quay.io/org/app:v2.0@sha256:abc; manager-xyz/kube-rbac-proxy:registry.redhat.io/openshift4/ose-kube-rbac-proxy:v4.18@sha256:def'
    );
  });
});
