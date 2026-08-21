/**
 * @jest-environment jsdom
 */

const fs = require('fs');
const path = require('path');

const filterJs = fs.readFileSync(
  path.join(__dirname, '../endpoint-filters.js'),
  'utf8'
);

// Note: Using eval() here is acceptable for test-only code with controlled input
// eslint-disable-next-line no-eval
eval(filterJs);

function rowHtml(text, status) {
  return `<tr data-status="${status}"><td>${text}</td></tr>` +
    '<tr class="detail-row"><td>details</td></tr>';
}

function buildPage() {
  document.body.innerHTML = `
    <input type="text" id="endpoint-search">
    <div class="filter-buttons">
      <button class="filter-btn active" data-filter="all" aria-pressed="true">All</button>
      <button class="filter-btn" data-filter="compliant" aria-pressed="false">Compliant</button>
      <button class="filter-btn" data-filter="closed" aria-pressed="false">Closed</button>
      <button class="filter-btn" data-filter="timeout" aria-pressed="false">Timeout</button>
      <button class="filter-btn" data-filter="other" aria-pressed="false">Other</button>
    </div>
    <div class="operator-group" id="group-a">
      <details><summary>op-a</summary>
        <div class="table-responsive"><table><tbody>
          ${rowHtml('10.0.0.1:8443 svc-a ns-a', 'compliant')}
          ${rowHtml('10.0.0.2:8080 svc-b ns-b', 'closed')}
        </tbody></table></div>
      </details>
    </div>
    <div class="operator-group" id="group-b">
      <details><summary>op-b</summary>
        <div class="table-responsive"><table><tbody>
          ${rowHtml('10.0.0.3:9090 svc-c ns-c', 'timeout')}
        </tbody></table></div>
      </details>
    </div>
    <span id="endpoint-filter-counts"></span>`;
}

function visibleRows() {
  return Array.from(document.querySelectorAll('tbody tr'))
    .filter((r) => !r.classList.contains('detail-row') && r.style.display !== 'none')
    .map((r) => r.textContent.trim());
}

function visibleGroups() {
  return Array.from(document.querySelectorAll('.operator-group'))
    .filter((g) => g.style.display !== 'none')
    .map((g) => g.id);
}

beforeEach(() => {
  buildPage();
  document.getElementById('endpoint-search').value = '';
  window.location.hash = '';
  currentEndpointFilter = 'all';
});

describe('parseEndpointHash', () => {
  test('returns an empty object when the hash is absent', () => {
    window.location.hash = '';
    expect(parseEndpointHash()).toEqual({});
  });

  test('parses key=value pairs and decodes components', () => {
    window.location.hash = '#status=closed&q=svc%20a';
    expect(parseEndpointHash()).toEqual({ status: 'closed', q: 'svc a' });
  });
});

describe('filterEndpointTable', () => {
  test('shows all rows when no search or filter is set', () => {
    filterEndpointTable();
    expect(visibleRows()).toHaveLength(3);
    expect(visibleGroups()).toEqual(['group-a', 'group-b']);
    expect(document.getElementById('endpoint-filter-counts').textContent).toBe('');
  });

  test('narrows rows by search text', () => {
    document.getElementById('endpoint-search').value = 'svc-b';
    filterEndpointTable();
    expect(visibleRows()).toEqual(['10.0.0.2:8080 svc-b ns-b']);
    expect(visibleGroups()).toEqual(['group-a']);
    expect(document.getElementById('endpoint-filter-counts').textContent)
      .toBe('Showing 1 of 3');
  });

  test('filters rows by status chip', () => {
    setEndpointStatusFilter('closed');
    expect(visibleRows()).toEqual(['10.0.0.2:8080 svc-b ns-b']);
    expect(visibleGroups()).toEqual(['group-a']);
    expect(window.location.hash).toBe('#status=closed');
  });

  test('hides the detail row with its parent row', () => {
    document.getElementById('endpoint-search').value = 'svc-a';
    filterEndpointTable();
    const detailRows = Array.from(document.querySelectorAll('.detail-row'));
    expect(detailRows[0].style.display).toBe('');
    expect(detailRows[1].style.display).toBe('none');
    expect(detailRows[2].style.display).toBe('none');
  });

  test('restores every row when the all chip is reselected', () => {
    setEndpointStatusFilter('timeout');
    expect(visibleRows()).toEqual(['10.0.0.3:9090 svc-c ns-c']);
    setEndpointStatusFilter('all');
    expect(visibleRows()).toHaveLength(3);
    expect(window.location.hash).toBe('');
  });
});

describe('setEndpointStatusFilter chip state', () => {
  test('activates the selected chip and deactivates the rest', () => {
    setEndpointStatusFilter('compliant');
    const active = document.querySelectorAll('.filter-btn.active');
    expect(active).toHaveLength(1);
    expect(active[0].getAttribute('data-filter')).toBe('compliant');
    expect(active[0].getAttribute('aria-pressed')).toBe('true');
    expect(document.querySelector('[data-filter="all"]').getAttribute('aria-pressed'))
      .toBe('false');
  });
});

describe('updateEndpointHash', () => {
  test('writes both search and status to the hash', () => {
    setEndpointStatusFilter('other');
    document.getElementById('endpoint-search').value = 'svc-c';
    filterEndpointTable();
    expect(window.location.hash).toBe('#status=other&q=svc-c');
  });
});

describe('bootstrap hash restore', () => {
  test('restores status and search from the hash on load', () => {
    window.location.hash = '#status=closed&q=svc-b';
    buildPage();
    jest.useFakeTimers();
    // Note: Using eval() here is acceptable for test-only code with controlled input
    // eslint-disable-next-line no-eval
    eval(filterJs);
    jest.runAllTimers();
    jest.useRealTimers();

    expect(currentEndpointFilter).toBe('closed');
    expect(document.getElementById('endpoint-search').value).toBe('svc-b');
    expect(visibleRows()).toEqual(['10.0.0.2:8080 svc-b ns-b']);
    expect(document.querySelector('.filter-btn.active').getAttribute('data-filter'))
      .toBe('closed');
  });

  test('falls back to all when the hash names an unknown chip', () => {
    window.location.hash = '#status=bogus';
    buildPage();
    jest.useFakeTimers();
    // Note: Using eval() here is acceptable for test-only code with controlled input
    // eslint-disable-next-line no-eval
    eval(filterJs);
    jest.runAllTimers();
    jest.useRealTimers();

    expect(currentEndpointFilter).toBe('all');
    expect(visibleRows()).toHaveLength(3);
    expect(document.querySelector('.filter-btn.active').getAttribute('data-filter'))
      .toBe('all');
  });
});
