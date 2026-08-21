---
layout: default
title: "Scan History"
---

<h1>Scan History</h1>

{% assign history = site.data.scan-history %}

<script>
window.historyData = [{% for scan in history %}{"scan_date":{{ scan.scan_date | jsonify }},"label":{{ scan.scan_date | date: "%Y-%m-%d %H:%M" | jsonify }},"mlkem_percent":{{ scan.summary.mlkem_percent | jsonify }}}{% unless forloop.last %},{% endunless %}{% endfor %}];
</script>

<div class="trend-chart-card">
  <h2>ML-KEM Trend</h2>
  <div id="mlkem-trend-chart"></div>
</div>

{% if history.size > 0 %}
<div class="filter-bar">
  <select id="ocp-filter" class="filter-select" onchange="filterHistoryTable()" aria-label="Filter by OCP version">
    <option value="">All OCP Versions</option>
  </select>
  <select id="tco-filter" class="filter-select" onchange="filterHistoryTable()" aria-label="Filter by TCO version">
    <option value="">All TCO Versions</option>
  </select>
  <span id="history-filter-counts"></span>
</div>

<div class="table-responsive">
<table class="data-table" id="history-table">
  <thead>
    <tr>
      <th class="sortable">Scan Date</th>
      <th class="sortable">Cluster</th>
      <th class="sortable" data-tooltip="OpenShift Container Platform version">OCP Version</th>
      <th class="sortable" data-tooltip="tls-compliance-operator version">TCO Version</th>
      <th class="sortable" data-type="number">Operators</th>
      <th class="sortable" data-type="number">Pass</th>
      <th class="sortable" data-type="number">Partial</th>
      <th class="sortable" data-type="number">None</th>
      <th class="sortable" data-type="number">Error</th>
      <th class="sortable" data-type="number" data-tooltip="Percentage of endpoints supporting ML-KEM">ML-KEM %</th>
      <th>Settings</th>
    </tr>
  </thead>
  <tbody>
    {% assign sorted_history = history | sort: "scan_date" | reverse %}
    {% for scan in sorted_history %}
    <tr data-ocp-version="{{ scan.ocp_version }}" data-tco-version="{% if scan.tco_version and scan.tco_version != '' %}{{ scan.tco_version }}{% else %}none{% endif %}">
      <td>{{ scan.scan_date | date: "%Y-%m-%d %H:%M" }}</td>
      <td>{{ scan.cluster }}</td>
      <td>{{ scan.ocp_version }}</td>
      <td>{% if scan.tco_version and scan.tco_version != "" %}{{ scan.tco_version }}{% else %}&mdash;{% endif %}</td>
      <td>{{ scan.summary.total_operators }}</td>
      <td>{{ scan.summary.pass }}</td>
      <td>{{ scan.summary.partial }}</td>
      <td>{{ scan.summary.none }}</td>
      <td>{{ scan.summary.error }}</td>
      <td>
        <div class="progress-container inline-progress">
          <div class="progress-bar">
            <div class="progress-fill" style="width: {{ scan.summary.mlkem_percent }}%"></div>
          </div>
          <span class="progress-label">{{ scan.summary.mlkem_percent }}%</span>
        </div>
      </td>
      <td>
        {% if scan.scan_settings %}
        <details>
          <summary>View</summary>
          <div class="scan-settings-detail">
            <dl>
              {% if scan.scan_settings.mode %}
              <dt>Mode</dt><dd>{{ scan.scan_settings.mode }}</dd>
              {% endif %}
              {% if scan.scan_settings.operator %}
              <dt>Operator</dt><dd>{{ scan.scan_settings.operator }}</dd>
              {% endif %}
              {% if scan.scan_settings.kubeconfig %}
              <dt>Kubeconfig</dt><dd><code>{{ scan.scan_settings.kubeconfig }}</code></dd>
              {% endif %}
              {% if scan.scan_settings.version %}
              <dt>Version</dt><dd>{{ scan.scan_settings.version }}</dd>
              {% endif %}
              {% if scan.scan_settings.keep_reports %}
              <dt>Keep Reports</dt><dd>Yes</dd>
              {% endif %}
            </dl>
          </div>
        </details>
        {% else %}
        <span class="text-muted">&mdash;</span>
        {% endif %}
      </td>
    </tr>
    {% if scan.operators and scan.operators.size > 0 %}
    <tr class="detail-row">
      <td colspan="11">
        <details>
          <summary>Operator Details ({{ scan.operators.size }} operators)</summary>
          <div class="endpoint-detail">
            <div class="detail-section" style="grid-column: 1 / -1;">
              <table class="detail-table">
                <thead>
                  <tr>
                    <th>Operator</th>
                    <th>Status</th>
                    <th>Version</th>
                    <th>Reachable Endpoints</th>
                    <th>ML-KEM Endpoints</th>
                    <th>ML-KEM %</th>
                  </tr>
                </thead>
                <tbody>
                  {% for op in scan.operators %}
                  <tr>
                    <td><strong>{{ op.name }}</strong></td>
                    <td>{% include status-badge.html status=op.status %}</td>
                    <td>{{ op.version | default: "&mdash;" }}</td>
                    <td>{{ op.reachable_endpoints }}</td>
                    <td>{{ op.mlkem_endpoints }}</td>
                    <td>{{ op.mlkem_percent }}%</td>
                  </tr>
                  {% endfor %}
                </tbody>
              </table>
            </div>
          </div>
        </details>
      </td>
    </tr>
    {% endif %}
    {% endfor %}
  </tbody>
</table>
</div>
{% else %}
<p class="no-data">No scan history available. Run <code>export-dashboard.sh</code> to populate.</p>
{% endif %}

<script src="{{ '/assets/js/history-filters.js' | relative_url }}"></script>
<script src="{{ '/assets/js/history-chart.js' | relative_url }}"></script>
