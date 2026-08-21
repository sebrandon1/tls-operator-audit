/**
 * @jest-environment jsdom
 */

const fs = require('fs');
const path = require('path');

const chartJs = fs.readFileSync(
  path.join(__dirname, '../history-chart.js'),
  'utf8'
);

// Note: Using eval() here is acceptable for test-only code with controlled input
// eslint-disable-next-line no-eval
eval(chartJs);

describe('trendChartPoints', () => {
  test('sorts entries oldest to newest and maps fields', () => {
    const points = trendChartPoints([
      { scan_date: '2026-08-20T00:00:00Z', label: '2026-08-20 00:00', mlkem_percent: 97 },
      { scan_date: '2026-08-01T00:00:00Z', label: '2026-08-01 00:00', mlkem_percent: 80 },
    ]);
    expect(points.map((p) => p.percent)).toEqual([80, 97]);
    expect(points[0].label).toBe('2026-08-01 00:00');
  });

  test('drops entries without a date or numeric percent', () => {
    const points = trendChartPoints([
      { scan_date: '2026-08-01T00:00:00Z', mlkem_percent: 80 },
      { mlkem_percent: 90 },
      { scan_date: '2026-08-02T00:00:00Z' },
      { scan_date: '2026-08-03T00:00:00Z', mlkem_percent: '94.4' },
      { scan_date: '2026-08-04T00:00:00Z', mlkem_percent: null },
      { scan_date: '2026-08-05T00:00:00Z', mlkem_percent: NaN },
      null,
    ]);
    expect(points).toHaveLength(1);
    expect(points[0].percent).toBe(80);
  });

  test('returns empty for non-array input', () => {
    expect(trendChartPoints(undefined)).toEqual([]);
    expect(trendChartPoints(null)).toEqual([]);
  });

  test('keeps scans at 0% ML-KEM', () => {
    const points = trendChartPoints([
      { scan_date: '2026-08-01T00:00:00Z', label: '2026-08-01 00:00', mlkem_percent: 0 },
      { scan_date: '2026-08-02T00:00:00Z', label: '2026-08-02 00:00', mlkem_percent: 50 },
    ]);
    expect(points.map((p) => p.percent)).toEqual([0, 50]);
  });
});

describe('renderTrendChart', () => {
  let container;

  beforeEach(() => {
    document.body.innerHTML = '<div id="mlkem-trend-chart"></div>';
    container = document.getElementById('mlkem-trend-chart');
  });

  test('renders an SVG polyline and one dot per point', () => {
    renderTrendChart(container, [
      { label: '2026-08-01 00:00', percent: 50 },
      { label: '2026-08-02 00:00', percent: 100 },
    ]);
    const svg = container.querySelector('svg');
    expect(svg).not.toBeNull();
    expect(container.querySelectorAll('polyline')).toHaveLength(1);
    expect(container.querySelectorAll('circle')).toHaveLength(2);
    expect(container.querySelector('.trend-dot title').textContent).toContain('50%');
  });

  test('labels the y axis in percent and the x axis with first and last dates', () => {
    renderTrendChart(container, [
      { label: '2026-08-01 00:00', percent: 25 },
      { label: '2026-08-02 00:00', percent: 75 },
    ]);
    const labels = Array.from(container.querySelectorAll('text')).map((t) => t.textContent);
    expect(labels).toContain('0%');
    expect(labels).toContain('50%');
    expect(labels).toContain('100%');
    expect(labels[labels.length - 2]).toBe('2026-08-01 00:00');
    expect(labels[labels.length - 1]).toBe('2026-08-02 00:00');
  });

  test('shows a message when fewer than two points exist', () => {
    renderTrendChart(container, [{ label: 'x', percent: 10 }]);
    expect(container.querySelector('svg')).toBeNull();
    expect(container.textContent).toContain('Not enough');
  });

  test('clears previous content before rendering', () => {
    container.innerHTML = '<p>stale</p>';
    renderTrendChart(container, [
      { label: 'a', percent: 0 },
      { label: 'b', percent: 100 },
    ]);
    expect(container.textContent).not.toContain('stale');
  });
});
