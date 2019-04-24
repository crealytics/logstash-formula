{%- from 'logstash/map.jinja' import logstash with context %}

{%- if logstash.use_upstream_repo %}
include:
  - .repo
{%- endif %}

logstash-pkg:
  pkg.{{logstash.pkgstate}}:
    - name: {{logstash.pkg}}
    {%- if logstash.use_upstream_repo %}
    - require:
      - pkgrepo: logstash-repo
      - pkg: {{ logstash.java }}
    {%- endif %}

{{ logstash.java }}:
  pkg.installed

# This gets around a user permissions bug with the logstash user/group
# being able to read /var/log/syslog, even if the group is properly set for
# the account. The group needs to be defined as 'adm' in the init script,
# so we'll do a pattern replace.

{% if salt['grains.get']('init' , None) != 'systemd'%}
{%- if salt['grains.get']('os', None) == "Ubuntu" %}
change service group in Ubuntu init script:
  file.replace:
    - name: /etc/init.d/logstash
    - pattern: "LS_GROUP=logstash"
    - repl: "LS_GROUP=adm"
    - watch_in:
      - service: logstash-svc

add adm group to logstash service account:
  user.present:
    - name: logstash
    - remove_groups: False
    - groups:
      - logstash
      - adm
    - require:
      - pkg: logstash-pkg
{%- endif %}
{% endif %}

logstash-config-dir-empty:
  file.directory:
    - name: /etc/logstash/conf.d
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - require:
      - pkg: logstash-pkg
    - clean: True

logstash-config-pipelines:
  file.managed:
    - name: /etc/logstash/pipelines.yml
    - user: root
    - group: root
    - mode: 755
    - source: salt://logstash/files/pipelines.yml
    - template: jinja
    - require:
      - pkg: logstash-pkg

{% for pipeline in logstash.pipelines %} {# Start of the pipelines for #}

logstash-config-{{ pipeline }}-dir:
  file.directory:
    - name: /etc/logstash/{{ pipeline }}
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - require:
      - pkg: logstash-pkg

{%- if logstash.pipelines[pipeline].inputs is defined %}
logstash-config-{{ pipeline }}-inputs:
  file.managed:
    - name: /etc/logstash/{{ pipeline }}/01-inputs.conf
    - user: root
    - group: root
    - mode: 755
    - source: salt://logstash/files/01-inputs.conf
    - template: jinja
    - context:
      pipeline: {{ pipeline }}
    - require:
      - pkg: logstash-pkg
{%- else %}
logstash-config-{{ pipeline }}-inputs:
  file.absent:
    - name: /etc/logstash/{{ pipeline }}/01-inputs.conf
{%- endif %}

{%- if logstash.pipelines[pipeline].filters is defined %}
logstash-config-{{ pipeline }}-filters:
  file.managed:
    - name: /etc/logstash/{{ pipeline }}/02-filters.conf
    - user: root
    - group: root
    - mode: 755
    - source: salt://logstash/files/02-filters.conf
    - template: jinja
    - context:
      pipeline: {{ pipeline }}
    - require:
      - pkg: logstash-pkg
{%- else %}
logstash-config-{{ pipeline }}-filters:
  file.absent:
    - name: /etc/logstash/{{ pipeline }}/02-filters.conf
{%- endif %}

{%- if logstash.pipelines[pipeline].outputs is defined %}
logstash-config-{{ pipeline }}-outputs:
  file.managed:
    - name: /etc/logstash/{{ pipeline }}/03-outputs.conf
    - user: root
    - group: root
    - mode: 755
    - source: salt://logstash/files/03-outputs.conf
    - template: jinja
    - context:
      pipeline: {{ pipeline }}
    - require:
      - pkg: logstash-pkg
{%- else %}
logstash-config-{{ pipeline }}-outputs:
  file.absent:
    - name: /etc/logstash/{{ pipeline }}/03-outputs.conf
{%- endif %}

{% endfor %} {# End of the pipelines for #}

logstash-svc:
  service.running:
    - name: {{logstash.svc}}
    - enable: true
    - require:
      - pkg: logstash-pkg
    - watch:
      - file: /etc/logstash/pipelines.yml
{% for pipeline in logstash.pipelines %} {# Start of the pipelines for #}
      - file: logstash-config-{{ pipeline }}-inputs
      - file: logstash-config-{{ pipeline }}-filters
      - file: logstash-config-{{ pipeline }}-outputs
{% endfor %} {# End of the pipelines for #}
