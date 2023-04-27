import 'dart:convert';
import 'dart:ui';

import 'package:candid_dart_core/core.dart';
import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/idea.dart';

import 'extensions.dart';
import 'notifiers.dart';
import 'res/assets.gen.dart';
import 'res/fonts.gen.dart';
import 'save/save_io.dart' if (dart.library.html) 'save/save_web.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'did2dart',
      scrollBehavior: const ScrollBehavior().copyWith(
        scrollbars: false,
        dragDevices: PointerDeviceKind.values.toSet(),
      ),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: FontFamily.agave,
      ),
      themeMode: ThemeMode.light,
      home: const MyHomePage(title: 'did2dart'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _dids =
      NewValueNotifier<List<MapEntry<PlatformFile, List<String>>>>([]);
  final _loading = ValueNotifier(false);
  final _options = NewValueNotifier(CodeOption());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          ValueListenableBuilder(
            valueListenable: _dids,
            builder: (context, value, child) {
              if (value.isEmpty) {
                return const SizedBox.shrink();
              }
              return IconButton(
                onPressed: () {
                  _dids.newValue(_dids.value..clear());
                },
                icon: const Icon(Icons.clear_all_rounded),
              );
            },
          ),
          const SizedBox(width: 12.0),
          ValueListenableBuilder(
            valueListenable: _dids,
            builder: (context, value, child) {
              if (value.isEmpty) {
                return const SizedBox.shrink();
              }
              return ElevatedButton.icon(
                onPressed: () {
                  save(value);
                },
                icon: const Icon(
                  Icons.download_rounded,
                  size: 16.0,
                ),
                label: Text('Download (${value.length})'),
              );
            },
          ),
          const SizedBox(width: 16.0),
        ],
      ),
      body: _buildMain(),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Pick .did',
        onPressed: () async {
          _loading.value = true;
          try {
            final result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['did'],
              allowMultiple: true,
              withReadStream: true,
            );
            final files = result?.files;
            if (files == null || files.isEmpty) {
              return;
            }
            final options = _options.value;
            final genOption = GenOption(
              freezed: options.freezed,
              equal: options.equal,
              copyWith: options.copyWith,
              makeCollectionsUnmodifiable: options.makeCollectionsUnmodifiable,
            );
            final list = <MapEntry<PlatformFile, List<String>>>[];
            for (final file in files) {
              final str = await file.readStream!.transform(utf8.decoder).first;
              final code = did2dart(file.name, str, genOption);
              final codes = code
                  .split('\n')
                  .slices(512)
                  .map((e) => e.join('\n'))
                  .toList();
              list.add(MapEntry(file, codes));
            }
            _dids.newValue(list);
          } finally {
            _loading.value = false;
          }
        },
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }

  Widget _buildOptions() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 8.0,
      ),
      child: ValueListenableBuilder(
        valueListenable: _options,
        builder: (context, options, child) {
          return Wrap(
            runSpacing: 8.0,
            spacing: 8.0,
            children: [
              ChoiceChip(
                selected: options.freezed,
                onSelected: (v) {
                  _options.newValue(options..freezed = v);
                },
                label: const Text("Freezed"),
              ),
              ChoiceChip(
                selected: options.copyWith,
                onSelected: (v) {
                  _options.newValue(options..copyWith = v);
                },
                label: const Text("CopyWith"),
              ),
              ChoiceChip(
                selected: options.equal,
                onSelected: (v) {
                  _options.newValue(options..equal = v);
                },
                label: const Text("Equal"),
              ),
              ChoiceChip(
                selected: options.makeCollectionsUnmodifiable,
                onSelected: (v) {
                  _options.newValue(options..makeCollectionsUnmodifiable = v);
                },
                label: const Text("CollectionsUnmodifiable"),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMain() {
    return ValueListenableBuilder(
      valueListenable: _loading,
      builder: (context, loading, child) {
        if (loading) {
          return Align(
            alignment: const AlignmentDirectional(0.0, -0.28),
            child: Assets.loading.lottie(
              width:
                  (MediaQuery.of(context).size.width * 0.8).coerceAtMost(720.0),
            ),
          );
        }
        return _buildBody();
      },
    );
  }

  Widget _buildBody() {
    return ValueListenableBuilder(
      valueListenable: _dids,
      builder: (context, value, child) {
        if (value.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildOptions(),
              Expanded(
                child: Align(
                  alignment: const AlignmentDirectional(0.0, -0.28),
                  child: Assets.empty.lottie(
                    width: (MediaQuery.of(context).size.width * 0.42)
                        .coerceAtMost(480.0),
                  ),
                ),
              ),
            ],
          );
        }
        return DefaultTabController(
          length: value.length,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTabBar(value),
              Expanded(
                child: _buildTabView(value),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabBar(List<MapEntry<PlatformFile, List<String>>> value) {
    return TabBar(
      isScrollable: true,
      tabs: List.generate(
        value.length,
        (index) {
          final entry = value[index];
          return Tab(
            height: 40.0,
            child: Row(
              children: [
                Text(entry.key.name),
                IconButton(
                  onPressed: () {
                    _dids.newValue(_dids.value..remove(entry));
                  },
                  icon: const Icon(
                    Icons.clear_rounded,
                    size: 14.0,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTabView(List<MapEntry<PlatformFile, List<String>>> value) {
    return TabBarView(
      children: List.generate(
        value.length,
        (index) {
          final entry = value[index];
          final codes = entry.value;
          final length = codes.length;
          return ListView.builder(
            itemBuilder: (context, index) {
              return HighlightView(
                codes[index],
                language: 'dart',
                textStyle: const TextStyle(
                  fontFamily: FontFamily.agave,
                  height: 1.5,
                ),
                theme: ideaTheme,
                padding: index == 0
                    ? const EdgeInsets.only(
                        left: 24.0,
                        right: 24.0,
                        top: 24.0,
                      )
                    : index == length - 1
                        ? const EdgeInsets.only(
                            left: 24.0,
                            right: 24.0,
                            bottom: 24.0,
                          )
                        : const EdgeInsets.symmetric(
                            horizontal: 24.0,
                          ),
              );
            },
            itemCount: length,
          );
        },
      ),
    );
  }
}

class CodeOption {
  bool freezed = false;

  bool makeCollectionsUnmodifiable = false;

  bool equal = true;

  bool copyWith = true;
}
