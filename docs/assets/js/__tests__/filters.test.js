/**
 * @jest-environment jsdom
 */

const fs = require('fs');
const path = require('path');

const filtersJs = fs.readFileSync(
  path.join(__dirname, '../filters.js'),
  'utf8'
);

function visibleRowNames() {
  return Array.from(document.querySelectorAll('#operator-table tbody tr'))
    .filter((row) => row.style.display !== 'none')
    .map((row) => row.getAttribute('data-name'));
}

function setupDom() {
  document.body.innerHTML = `
    <input id="table-search" type="text" value="">
    <button class="filter-btn active" data-filter="all" aria-pressed="true">All</button>
    <button class="filter-btn" data-filter="pass" aria-pressed="false">Pass</button>
    <button class="filter-btn" data-filter="partial" aria-pressed="false">Partial</button>
    <button class="filter-btn" data-filter="error" aria-pressed="false">Error</button>
    <span id="filter-counts"></span>
    <table id="operator-table">
      <tbody>
        <tr data-status="pass" data-name="pass-op"><td>pass-op redhat-operators</td></tr>
        <tr data-status="partial" data-name="partial-op"><td>partial-op certified</td></tr>
        <tr data-status="error" data-name="fail-op"><td>fail-op missing report</td></tr>
      </tbody>
    </table>
  `;
}

setupDom();
window.history.replaceState(null, '', '/dashboard');
// Note: Using eval() here is acceptable for test-only code with controlled input
// eslint-disable-next-line no-eval
eval(filtersJs);

describe('parseHash', () => {
  beforeEach(() => {
    setupDom();
    window.history.replaceState(null, '', '/dashboard');
    currentFilter = 'all';
  });

  test('returns empty object when hash is missing', () => {
    expect(parseHash()).toEqual({});
  });

  test('parses status and search query', () => {
    window.location.hash = '#status=pass&q=rhoai';
    expect(parseHash()).toEqual({ status: 'pass', q: 'rhoai' });
  });

  test('decodes URI-encoded search values', () => {
    window.location.hash = '#q=pass%20op';
    expect(parseHash()).toEqual({ q: 'pass op' });
  });

  test('skips hash parts without an equals sign', () => {
    window.location.hash = '#broken&status=error';
    expect(parseHash()).toEqual({ status: 'error' });
  });
});

describe('filterTable', () => {
  beforeEach(() => {
    setupDom();
    window.history.replaceState(null, '', '/dashboard');
    currentFilter = 'all';
    document.getElementById('table-search').value = '';
  });

  test('shows all rows by default', () => {
    filterTable();
    expect(visibleRowNames()).toEqual(['pass-op', 'partial-op', 'fail-op']);
    expect(document.getElementById('filter-counts').textContent).toBe('');
  });

  test('filters rows by status', () => {
    setStatusFilter('pass');
    expect(visibleRowNames()).toEqual(['pass-op']);
    expect(document.getElementById('filter-counts').textContent).toBe('Showing 1 of 3');
    expect(document.querySelector('[data-filter="pass"]').classList.contains('active')).toBe(true);
    expect(document.querySelector('[data-filter="pass"]').getAttribute('aria-pressed')).toBe('true');
    expect(document.querySelector('[data-filter="all"]').classList.contains('active')).toBe(false);
  });

  test('filters rows by search text', () => {
    document.getElementById('table-search').value = 'certified';
    filterTable();
    expect(visibleRowNames()).toEqual(['partial-op']);
  });

  test('applies status and search together', () => {
    document.getElementById('table-search').value = 'op';
    setStatusFilter('error');
    expect(visibleRowNames()).toEqual(['fail-op']);
  });

  test('writes status and query into the location hash', () => {
    document.getElementById('table-search').value = 'pass op';
    setStatusFilter('pass');
    expect(window.location.hash).toBe('#status=pass&q=pass%20op');
  });

  test('clears the hash when showing all rows with an empty search', () => {
    setStatusFilter('pass');
    setStatusFilter('all');
    expect(window.location.hash).toBe('');
  });

  test('returns early when the operator table is missing', () => {
    document.getElementById('operator-table').remove();
    expect(() => filterTable()).not.toThrow();
  });
});

describe('hash routing', () => {
  beforeEach(() => {
    setupDom();
    window.history.replaceState(null, '', '/dashboard');
    currentFilter = 'all';
  });

  test('applies status and search from the URL hash', () => {
    window.location.hash = '#status=partial&q=certified';
    const parsed = parseHash();
    currentFilter = parsed.status;
    document.getElementById('table-search').value = parsed.q;
    setStatusFilter(parsed.status);

    expect(document.getElementById('table-search').value).toBe('certified');
    expect(visibleRowNames()).toEqual(['partial-op']);
    expect(document.querySelector('[data-filter="partial"]').classList.contains('active')).toBe(true);
  });
});
