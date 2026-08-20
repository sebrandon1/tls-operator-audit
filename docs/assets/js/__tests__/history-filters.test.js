/**
 * @jest-environment jsdom
 */

const fs = require('fs');
const path = require('path');

const historyFiltersJs = fs.readFileSync(
  path.join(__dirname, '../history-filters.js'),
  'utf8'
);

function setupHistoryDom() {
  document.body.innerHTML = `
    <select id="ocp-filter">
      <option value="">All OCP Versions</option>
    </select>
    <select id="tco-filter">
      <option value="">All TCO Versions</option>
    </select>
    <span id="history-filter-counts"></span>
    <table id="history-table">
      <tbody>
        <tr data-name="scan-418" data-ocp-version="4.18.0" data-tco-version="v1.1.8"><td>4.18</td></tr>
        <tr class="detail-row" data-name="scan-418-detail"><td>4.18 detail</td></tr>
        <tr data-name="scan-419" data-ocp-version="4.19.0" data-tco-version="v1.1.9"><td>4.19</td></tr>
        <tr class="detail-row" data-name="scan-419-detail"><td>4.19 detail</td></tr>
        <tr data-name="scan-50" data-ocp-version="5.0" data-tco-version="none"><td>5.0</td></tr>
        <tr class="detail-row" data-name="scan-50-detail"><td>5.0 detail</td></tr>
        <tr data-name="scan-419b" data-ocp-version="4.19.0" data-tco-version="v1.1.8"><td>4.19 older tco</td></tr>
      </tbody>
    </table>
  `;
}

function optionValues(selectId) {
  return Array.from(document.getElementById(selectId).options).map(
    (option) => option.value
  );
}

function visibleRowNames() {
  return Array.from(document.querySelectorAll('#history-table tbody tr'))
    .filter((row) => row.style.display !== 'none')
    .map((row) => row.getAttribute('data-name'));
}

setupHistoryDom();
window.history.replaceState(null, '', '/history');
// Note: Using eval() here is acceptable for test-only code with controlled input
// eslint-disable-next-line no-eval
eval(historyFiltersJs);

describe('history filters', () => {
  beforeEach(() => {
    setupHistoryDom();
    jest.useFakeTimers();
    // Re-run the IIFE so dropdowns are populated for the fresh DOM.
    // eslint-disable-next-line no-eval
    eval(historyFiltersJs);
    jest.runAllTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  test('populates OCP versions in reverse natural order', () => {
    expect(optionValues('ocp-filter')).toEqual([
      '',
      '5.0',
      '4.19.0',
      '4.18.0',
    ]);
  });

  test('populates TCO versions and a None option', () => {
    expect(optionValues('tco-filter')).toEqual([
      '',
      'v1.1.9',
      'v1.1.8',
      'none',
    ]);
    expect(document.querySelector('#tco-filter option[value="none"]').textContent).toBe(
      'None'
    );
  });

  test('filters by OCP version and hides matching detail rows', () => {
    document.getElementById('ocp-filter').value = '4.19.0';
    filterHistoryTable();
    expect(visibleRowNames()).toEqual([
      'scan-419',
      'scan-419-detail',
      'scan-419b',
    ]);
    expect(document.getElementById('history-filter-counts').textContent).toBe(
      'Showing 2 of 4'
    );
  });

  test('filters by TCO none and keeps the detail row attached', () => {
    document.getElementById('tco-filter').value = 'none';
    filterHistoryTable();
    expect(visibleRowNames()).toEqual(['scan-50', 'scan-50-detail']);
  });

  test('applies OCP and TCO filters together', () => {
    document.getElementById('ocp-filter').value = '4.19.0';
    document.getElementById('tco-filter').value = 'v1.1.8';
    filterHistoryTable();
    expect(visibleRowNames()).toEqual(['scan-419b']);
  });

  test('clears the count label when every scan is visible', () => {
    filterHistoryTable();
    expect(visibleRowNames().filter((name) => !name.includes('detail'))).toEqual([
      'scan-418',
      'scan-419',
      'scan-50',
      'scan-419b',
    ]);
    expect(document.getElementById('history-filter-counts').textContent).toBe('');
  });

  test('returns early when the history table is missing', () => {
    document.getElementById('history-table').remove();
    expect(() => filterHistoryTable()).not.toThrow();
  });
});
