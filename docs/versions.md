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
  <div class="card" data-tooltip="Total operators with index version tracking">
    <div class="card-number">{{ total }}</div>
    <div class="card-label">Tracked</div>
  </div>
  <div class="card card-pass" data-tooltip="Operators running the latest index version">
    <div class="card-number">{{ total | minus: updates.size }}</div>
    <div class="card-label">Up to Date</div>
  </div>
  {% if updates.size > 0 %}
  <div class="card card-partial" data-tooltip="Operators with newer index versions available">
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
      <th class="sortable" data-tooltip="Operator catalog index image">Index</th>
      <th class="sortable" data-tooltip="Index image tag">Tag</th>
      <th class="sortable">Channel</th>
      <th class="sortable" data-tooltip="Latest version in the catalog index">Index Version</th>
      <th class="sortable" data-tooltip="Version found during last scan">Scanned Version</th>
      <th class="sortable">Status</th>
    </tr>
  </thead>
  <tbody>
    {% for op in data.operators %}
    <tr>
      <td><a href="{{ '/operators/' | append: op.name | relative_url }}">{{ op.name }}</a></td>
      {% if op.catalog_image and op.catalog_image != "" %}
        {% assign image_with_tag = op.catalog_image | split: "/" | last %}
        {% assign index_name = image_with_tag | split: ":" | first %}
        {% assign index_tag = image_with_tag | split: ":" | last %}
        <td>
          {% if op.catalog_url and op.catalog_url != "" %}
            <a href="{{ op.catalog_url }}" target="_blank" rel="noopener">{{ index_name }}</a>
          {% else %}
            {{ index_name }}
          {% endif %}
        </td>
        <td>{{ index_tag }}</td>
      {% else %}
        <td>{{ op.catalog }}</td>
        <td>&mdash;</td>
      {% endif %}
      <td>{{ op.channel | default: "&mdash;" }}</td>
      <td>{{ op.index_version | default: "&mdash;" }}</td>
      <td>{{ op.scanned_version | default: "&mdash;" }}</td>
      <td>
        {% if op.update_available %}
          <span class="badge badge-partial" data-tooltip="A newer version exists in the catalog index">Update Available</span>
        {% elsif op.error %}
          <span class="badge badge-error">{{ op.error }}</span>
        {% elsif op.version_changed %}
          <span class="badge badge-pqc" data-tooltip="Index image changed but version is the same">Index Changed</span>
        {% else %}
          <span class="badge badge-pass" data-tooltip="Running the latest available version">Current</span>
        {% endif %}
      </td>
    </tr>
    {% endfor %}
  </tbody>
</table>
</div>
