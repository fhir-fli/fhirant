import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/server_state.dart';

class ResourceBrowserScreen extends StatefulWidget {
  final R4ResourceType? initialType;

  const ResourceBrowserScreen({super.key, this.initialType});

  @override
  State<ResourceBrowserScreen> createState() => _ResourceBrowserScreenState();
}

class _ResourceBrowserScreenState extends State<ResourceBrowserScreen> {
  R4ResourceType? _selectedType;
  List<Resource>? _resources;
  bool _loading = false;
  bool _showYaml = false;
  int _page = 0;
  bool _hasMore = true;
  static const _pageSize = 50;

  // Stack of single-resource views navigated via reference taps.
  // Each entry is (reference label, resource).
  final List<(String, Resource)> _refStack = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialType != null) {
      _selectedType = widget.initialType;
      _loadResources();
    }
  }

  Future<void> _loadResources({bool append = false}) async {
    if (_selectedType == null) return;
    setState(() => _loading = true);

    try {
      final db = context.read<ServerState>().db;
      final results = await db.getResourcesWithPagination(
        resourceType: _selectedType!,
        count: _pageSize,
        offset: append ? (_page + 1) * _pageSize : 0,
      );

      setState(() {
        if (append) {
          _page++;
          _resources = [...?_resources, ...results];
        } else {
          _page = 0;
          _resources = results;
        }
        _hasMore = results.length == _pageSize;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading resources: $e')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  void _onTypeSelected(R4ResourceType type) {
    setState(() {
      _selectedType = type;
      _resources = null;
      _refStack.clear();
    });
    _loadResources();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ServerState>(
      builder: (context, state, _) {
        final counts = state.resourceCounts;
        final types = counts.keys.toList()
          ..sort((a, b) => a.toString().compareTo(b.toString()));

        final showingRef = _refStack.isNotEmpty;
        final title = showingRef
            ? _refStack.last.$1
            : _selectedType?.toString() ?? 'Resource Browser';

        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            leading: showingRef
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => setState(() => _refStack.removeLast()),
                  )
                : null,
            actions: [
              if (_resources != null || showingRef)
                IconButton(
                  icon: Icon(_showYaml ? Icons.data_object : Icons.subject),
                  tooltip: _showYaml ? 'Switch to JSON' : 'Switch to YAML',
                  onPressed: () => setState(() => _showYaml = !_showYaml),
                ),
            ],
          ),
          body: Row(
            children: [
              // Type selector sidebar (or drawer on narrow screens)
              if (MediaQuery.of(context).size.width >= 600)
                SizedBox(
                  width: 220,
                  child: _buildTypeList(types, counts),
                )
              else if (_selectedType == null && !showingRef)
                Expanded(child: _buildTypeList(types, counts)),
              // Single resource view from reference navigation
              if (showingRef)
                Expanded(child: _buildSingleResourceView())
              // Resource list
              else if (_selectedType != null)
                Expanded(child: _buildResourceList()),
            ],
          ),
          // On narrow screens, show back-to-types button
          floatingActionButton:
              MediaQuery.of(context).size.width < 600 &&
                      _selectedType != null &&
                      !showingRef
                  ? FloatingActionButton.small(
                      onPressed: () => setState(() {
                        _selectedType = null;
                        _resources = null;
                      }),
                      child: const Icon(Icons.list),
                    )
                  : null,
        );
      },
    );
  }

  Widget _buildTypeList(
      List<R4ResourceType> types, Map<R4ResourceType, int> counts) {
    if (types.isEmpty) {
      return const Center(child: Text('No resources in database'));
    }

    return ListView.builder(
      itemCount: types.length,
      itemBuilder: (context, index) {
        final type = types[index];
        final count = counts[type] ?? 0;
        final selected = type == _selectedType;

        return ListTile(
          title: Text(
            type.toString(),
            style: TextStyle(
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
          trailing: Text(
            count.toString(),
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
            ),
          ),
          selected: selected,
          selectedTileColor:
              Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
          onTap: () => _onTypeSelected(type),
        );
      },
    );
  }

  Widget _buildResourceList() {
    if (_loading && _resources == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_resources == null || _resources!.isEmpty) {
      return const Center(child: Text('No resources found'));
    }

    return ListView.builder(
      itemCount: _resources!.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _resources!.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      onPressed: () => _loadResources(append: true),
                      child: const Text('Load More'),
                    ),
            ),
          );
        }

        final resource = _resources![index];
        final id = resource.id?.primitiveValue ?? '(no id)';
        final subtitle = _getResourceSubtitle(resource);

        return _ResourceTile(
          key: ValueKey('${resource.resourceType}/$id'),
          resource: resource,
          id: id,
          subtitle: subtitle,
          showYaml: _showYaml,
          onReferenceTap: _handleReferenceTap,
        );
      },
    );
  }

  Widget _buildSingleResourceView() {
    final (label, resource) = _refStack.last;
    final id = resource.id?.primitiveValue ?? '(no id)';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: _ResourceTile(
        key: ValueKey('ref-$label'),
        resource: resource,
        id: id,
        subtitle: _getResourceSubtitle(resource),
        showYaml: _showYaml,
        onReferenceTap: _handleReferenceTap,
        initiallyExpanded: true,
      ),
    );
  }

  String _getResourceSubtitle(Resource resource) {
    final json = resource.toJson();
    // Try to extract a human-readable summary
    if (json.containsKey('name')) {
      final name = json['name'];
      if (name is List && name.isNotEmpty) {
        final first = name[0] as Map<String, dynamic>;
        final parts = <String>[];
        if (first['family'] != null) parts.add(first['family'].toString());
        if (first['given'] is List) {
          parts.addAll((first['given'] as List).map((e) => e.toString()));
        }
        if (parts.isNotEmpty) return parts.join(' ');
      } else if (name is String) {
        return name;
      }
    }
    if (json.containsKey('code')) {
      final code = json['code'];
      if (code is Map<String, dynamic>) {
        if (code['text'] != null) return code['text'].toString();
        if (code['coding'] is List) {
          final coding = (code['coding'] as List).first as Map<String, dynamic>;
          return coding['display']?.toString() ??
              coding['code']?.toString() ??
              '';
        }
      }
    }
    if (json.containsKey('status')) return 'Status: ${json['status']}';
    return '';
  }

  void _handleReferenceTap(String reference) async {
    // Check if it's a URL
    if (reference.startsWith('http://') || reference.startsWith('https://')) {
      final uri = Uri.tryParse(reference);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    // Try to parse as ResourceType/id reference
    final parts = reference.split('/');
    if (parts.length >= 2) {
      final typeName = parts[parts.length - 2];
      final id = parts[parts.length - 1];

      try {
        final type = R4ResourceType.values.firstWhere(
          (t) => t.toString() == typeName,
        );
        final db = context.read<ServerState>().db;
        final resource = await db.getResource(type, id);
        if (resource != null && mounted) {
          setState(() => _refStack.add((reference, resource)));
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Resource $reference not found')),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Unknown resource type: $typeName')),
          );
        }
      }
    }
  }
}

class _ResourceTile extends StatefulWidget {
  final Resource resource;
  final String id;
  final String subtitle;
  final bool showYaml;
  final void Function(String reference) onReferenceTap;
  final bool initiallyExpanded;

  const _ResourceTile({
    super.key,
    required this.resource,
    required this.id,
    required this.subtitle,
    required this.showYaml,
    required this.onReferenceTap,
    this.initiallyExpanded = false,
  });

  @override
  State<_ResourceTile> createState() => _ResourceTileState();
}

class _ResourceTileState extends State<_ResourceTile> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        children: [
          ListTile(
            title: Text(
              widget.id,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            subtitle: widget.subtitle.isNotEmpty
                ? Text(
                    widget.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
            trailing: Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 500),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: _buildResourceContent(theme),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResourceContent(ThemeData theme) {
    final json = widget.resource.toJson();

    if (widget.showYaml) {
      final yaml = _jsonToYaml(json, 0);
      return _buildRichText(yaml, theme);
    } else {
      final jsonStr =
          const JsonEncoder.withIndent('  ').convert(json);
      return _buildRichText(jsonStr, theme);
    }
  }

  Widget _buildRichText(String content, ThemeData theme) {
    // Parse the content and make references/URLs tappable
    final spans = <InlineSpan>[];
    final lines = content.split('\n');

    for (var i = 0; i < lines.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: '\n'));
      _addLineSpans(lines[i], spans, theme);
    }

    return SelectableText.rich(
      TextSpan(
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: theme.colorScheme.onSurface,
        ),
        children: spans,
      ),
    );
  }

  void _addLineSpans(
      String line, List<InlineSpan> spans, ThemeData theme) {
    // Match URLs and FHIR references (ResourceType/id patterns)
    final urlRegex = RegExp(r'https?://[^\s",}\]]+');
    // Match "SomeType/some-id" patterns — validated against R4ResourceType
    final refRegex = RegExp(r'"([A-Z][a-zA-Z]+/[A-Za-z0-9._-]+)"');

    var lastEnd = 0;
    final allMatches = <_LinkMatch>[];

    for (final match in urlRegex.allMatches(line)) {
      allMatches.add(_LinkMatch(match.start, match.end, match.group(0)!));
    }
    for (final match in refRegex.allMatches(line)) {
      final ref = match.group(1)!;
      final typeName = ref.split('/').first;
      // Only treat as a reference if the type is a valid FHIR resource type
      final isValidType = R4ResourceType.values.any((t) => t.toString() == typeName);
      if (isValidType) {
        allMatches
            .add(_LinkMatch(match.start + 1, match.end - 1, ref));
      }
    }

    allMatches.sort((a, b) => a.start.compareTo(b.start));

    // Remove overlaps
    final filtered = <_LinkMatch>[];
    for (final m in allMatches) {
      if (filtered.isEmpty || m.start >= filtered.last.end) {
        filtered.add(m);
      }
    }

    for (final m in filtered) {
      if (m.start > lastEnd) {
        spans.add(TextSpan(text: line.substring(lastEnd, m.start)));
      }
      spans.add(
        WidgetSpan(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => widget.onReferenceTap(m.text),
              child: Text(
                m.text,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ),
      );
      lastEnd = m.end;
    }

    if (lastEnd < line.length) {
      spans.add(TextSpan(text: line.substring(lastEnd)));
    }
    if (lastEnd == 0 && filtered.isEmpty) {
      spans.add(TextSpan(text: line));
    }
  }

  ThemeData get theme => Theme.of(context);
}

class _LinkMatch {
  final int start;
  final int end;
  final String text;
  _LinkMatch(this.start, this.end, this.text);
}

String _jsonToYaml(dynamic value, int indent) {
  final prefix = '  ' * indent;

  if (value == null) return 'null';
  if (value is bool) return value.toString();
  if (value is num) return value.toString();
  if (value is String) {
    if (value.contains('\n')) {
      final lines = value.split('\n');
      final buf = StringBuffer('|\n');
      for (final line in lines) {
        buf.write('$prefix  $line\n');
      }
      return buf.toString().trimRight();
    }
    if (value.contains(':') ||
        value.contains('#') ||
        value.contains('"') ||
        value.contains("'") ||
        value.startsWith('{') ||
        value.startsWith('[') ||
        value.startsWith('*') ||
        value.startsWith('&') ||
        value.isEmpty) {
      return '"${value.replaceAll('"', r'\"')}"';
    }
    return value;
  }

  if (value is List) {
    if (value.isEmpty) return '[]';
    final buf = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      if (i > 0) buf.write('\n');
      final item = value[i];
      if (item is Map) {
        buf.write('$prefix- ');
        final entries = item.entries.toList();
        for (var j = 0; j < entries.length; j++) {
          final e = entries[j];
          if (j == 0) {
            final val = _jsonToYaml(e.value, indent + 2);
            if (e.value is Map || e.value is List) {
              buf.write('${e.key}:\n$val');
            } else {
              buf.write('${e.key}: $val');
            }
          } else {
            buf.write('\n$prefix  ');
            final val = _jsonToYaml(e.value, indent + 2);
            if (e.value is Map || e.value is List) {
              buf.write('${e.key}:\n$val');
            } else {
              buf.write('${e.key}: $val');
            }
          }
        }
      } else {
        buf.write('$prefix- ${_jsonToYaml(item, indent + 1)}');
      }
    }
    return buf.toString();
  }

  if (value is Map) {
    if (value.isEmpty) return '{}';
    final buf = StringBuffer();
    var first = true;
    for (final entry in value.entries) {
      if (!first) buf.write('\n');
      first = false;
      final val = _jsonToYaml(entry.value, indent + 1);
      if (entry.value is Map || entry.value is List) {
        buf.write('$prefix${entry.key}:\n$val');
      } else {
        buf.write('$prefix${entry.key}: $val');
      }
    }
    return buf.toString();
  }

  return value.toString();
}
