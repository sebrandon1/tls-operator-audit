// ML-KEM trend chart for the Scan History page.
// Reads window.historyData (slim {scan_date, label, mlkem_percent} entries
// injected by history.md — label is pre-formatted by Liquid so chart and
// table times always agree) and renders an inline SVG line chart of
// mlkem_percent over time into #mlkem-trend-chart.

// Normalize raw history entries into {label, percent} points sorted oldest first.
function trendChartPoints(historyData) {
  if (!Array.isArray(historyData)) return [];
  return historyData
    .filter(function(scan) {
      return scan && scan.scan_date && Number.isFinite(scan.mlkem_percent);
    })
    .sort(function(a, b) {
      return new Date(a.scan_date) - new Date(b.scan_date);
    })
    .map(function(scan) {
      return { label: scan.label, percent: scan.mlkem_percent };
    });
}

function svgEl(tag, attrs, text) {
  var el = document.createElementNS('http://www.w3.org/2000/svg', tag);
  for (var key in attrs) el.setAttribute(key, attrs[key]);
  if (text != null) el.textContent = text;
  return el;
}

function axisLabel(x, y, anchor, text) {
  return svgEl('text', {
    x: x, y: y, 'class': 'trend-axis-label', 'text-anchor': anchor
  }, text);
}

function renderTrendChart(container, points) {
  container.innerHTML = '';

  if (points.length < 2) {
    var msg = document.createElement('p');
    msg.className = 'trend-chart-empty';
    msg.textContent = 'Not enough scans yet to plot an ML-KEM trend.';
    container.appendChild(msg);
    return;
  }

  var W = 640, H = 180;
  var left = 44, right = 12, top = 12, bottom = 28;
  var plotW = W - left - right;
  var plotH = H - top - bottom;

  function xPos(i) {
    return left + plotW * (i / (points.length - 1));
  }
  // Fixed 0-100% scale so scans stay comparable regardless of range.
  function yPos(pct) {
    return top + plotH * (1 - pct / 100);
  }
  function pt(i, pct) {
    return { x: xPos(i).toFixed(1), y: yPos(pct).toFixed(1) };
  }

  var svg = svgEl('svg', {
    viewBox: '0 0 ' + W + ' ' + H,
    'class': 'trend-chart',
    role: 'img',
    'aria-label': 'ML-KEM support percentage across past scans'
  });

  [0, 25, 50, 75, 100].forEach(function(pct) {
    var y = yPos(pct);
    svg.appendChild(svgEl('line', {
      x1: left, x2: W - right, y1: y, y2: y, 'class': 'trend-grid'
    }));
    if (pct % 50 === 0) {
      svg.appendChild(axisLabel(left - 8, y + 4, 'end', pct + '%'));
    }
  });

  svg.appendChild(svgEl('polyline', {
    points: points.map(function(p, i) {
      var q = pt(i, p.percent);
      return q.x + ',' + q.y;
    }).join(' '),
    'class': 'trend-line',
    fill: 'none'
  }));

  points.forEach(function(p, i) {
    var q = pt(i, p.percent);
    var dot = svgEl('circle', {
      cx: q.x,
      cy: q.y,
      r: 4,
      'class': 'trend-dot'
    });
    dot.appendChild(svgEl('title', {}, p.label + ' — ' + p.percent + '% ML-KEM'));
    svg.appendChild(dot);
  });

  svg.appendChild(axisLabel(left, H - 8, 'start', points[0].label));
  svg.appendChild(axisLabel(W - right, H - 8, 'end', points[points.length - 1].label));

  container.appendChild(svg);
}

(function() {
  setTimeout(function() {
    var container = document.getElementById('mlkem-trend-chart');
    if (!container || !window.historyData) return;
    renderTrendChart(container, trendChartPoints(window.historyData));
  }, 0);
})();
