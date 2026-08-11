---
layout: default
title: "Index Versions"
---

{% assign data = site.data.index-versions %}

<div class="scan-info">
  <span>Last checked: <strong>{{ data.checked | date: "%Y-%m-%d %H:%M" }}</strong></span>
</div>

{% assign updates = data.operators | where: "update_available", true %}
{% assign total = data.operators | size %}

<div class="summary-cards">
  <div class="card">
    <div class="card-number">{{ total }}</div>
    <div class="card-label">Tracked</div>
  </div>
  <div class="card card-pass">
    <div class="card-number">{{ total | minus: updates.size }}</div>
    <div class="card-label">Up to Date</div>
  </div>
  {% if updates.size > 0 %}
  <div class="card card-partial">
    <div class="card-number">{{ updates.size }}</div>
    <div class="card-label">Updates Available</div>
  </div>
  {% endif %}
</div>

<h2>Operator Index Versions</h2>

<div class="table-responsive">
<table class="data-table" id="versions-table">
  <thead>
    <tr>
      <th class="sortable">Operator</th>
      <th class="sortable">Catalog</th>
      <th class="sortable">Channel</th>
      <th class="sortable">Index Version</th>
      <th class="sortable">Scanned Version</th>
      <th class="sortable">Status</th>
    </tr>
  </thead>
  <tbody>
    {% for op in data.operators %}
    <tr>
      <td><a href="{{ '/operators/' | append: op.name | relative_url }}">{{ op.name }}</a></td>
      <td>
        {% if op.catalog_url and op.catalog_url != "" %}
          <a href="{{ op.catalog_url }}" target="_blank" rel="noopener">{{ op.catalog }}</a>
        {% else %}
          {{ op.catalog }}
        {% endif %}
      </td>
      <td>{{ op.channel | default: "&mdash;" }}</td>
      <td>{{ op.index_version | default: "&mdash;" }}</td>
      <td>{{ op.scanned_version | default: "&mdash;" }}</td>
      <td>
        {% if op.update_available %}
          <span class="badge badge-partial">Update Available</span>
        {% elsif op.error %}
          <span class="badge badge-error">{{ op.error }}</span>
        {% elsif op.version_changed %}
          <span class="badge badge-pqc">Index Changed</span>
        {% else %}
          <span class="badge badge-pass">Current</span>
        {% endif %}
      </td>
    </tr>
    {% endfor %}
  </tbody>
</table>
</div>
