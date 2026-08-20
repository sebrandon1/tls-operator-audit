/**
 * @jest-environment jsdom
 */

const fs = require('fs');
const path = require('path');

const sortJs = fs.readFileSync(
  path.join(__dirname, '../sort.js'),
  'utf8'
);

function rowOrder() {
  return Array.from(document.querySelector('#operator-table tbody').rows).map(
    (row) => row.getAttribute('data-name') || row.textContent.trim()
  );
}

function clickHeader(label) {
  const th = Array.from(document.querySelectorAll('th.sortable')).find(
    (header) => header.textContent === label
  );
  th.dispatchEvent(new MouseEvent('click', { bubbles: true }));
}

describe('sortable tables', () => {
  beforeEach(() => {
    document.body.innerHTML = `
      <table id="operator-table">
        <thead>
          <tr>
            <th class="sortable">Operator</th>
            <th class="sortable" data-type="number">Endpoints</th>
          </tr>
        </thead>
        <tbody>
          <tr data-name="bravo"><td>bravo</td><td data-sort="2">2</td></tr>
          <tr class="detail-row" data-name="bravo-detail"><td colspan="2">bravo detail</td></tr>
          <tr data-name="alpha"><td>alpha</td><td data-sort="10">10</td></tr>
          <tr class="detail-row" data-name="alpha-detail"><td colspan="2">alpha detail</td></tr>
          <tr data-name="charlie"><td>charlie</td><td data-sort="1">1</td></tr>
        </tbody>
      </table>
    `;
    // Note: Using eval() here is acceptable for test-only code with controlled input
    // eslint-disable-next-line no-eval
    eval(sortJs);
  });

  test('sets aria-sort none on sortable headers', () => {
    document.querySelectorAll('th.sortable').forEach((th) => {
      expect(th.getAttribute('aria-sort')).toBe('none');
    });
  });

  test('sorts text columns and keeps detail rows with their parent', () => {
    clickHeader('Operator');
    expect(rowOrder()).toEqual([
      'alpha',
      'alpha-detail',
      'bravo',
      'bravo-detail',
      'charlie',
    ]);
    expect(document.querySelector('th.sortable').getAttribute('aria-sort')).toBe(
      'ascending'
    );

    clickHeader('Operator');
    expect(rowOrder()).toEqual([
      'charlie',
      'bravo',
      'bravo-detail',
      'alpha',
      'alpha-detail',
    ]);
    expect(document.querySelector('th.sortable').getAttribute('aria-sort')).toBe(
      'descending'
    );
  });

  test('sorts numeric columns using data-sort', () => {
    clickHeader('Endpoints');
    expect(rowOrder().filter((name) => !name.includes('detail'))).toEqual([
      'charlie',
      'bravo',
      'alpha',
    ]);

    clickHeader('Endpoints');
    expect(rowOrder().filter((name) => !name.includes('detail'))).toEqual([
      'alpha',
      'bravo',
      'charlie',
    ]);
  });

  test('does nothing when a table has no tbody', () => {
    document.body.innerHTML = `
      <table>
        <thead>
          <tr><th class="sortable">Name</th></tr>
        </thead>
      </table>
    `;
    // eslint-disable-next-line no-eval
    eval(sortJs);
    const th = document.querySelector('th.sortable');
    expect(() =>
      th.dispatchEvent(new MouseEvent('click', { bubbles: true }))
    ).not.toThrow();
  });
});
