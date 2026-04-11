import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:intl/intl.dart';
import '../services/recording_service.dart';

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  List<File> _recordings = [];
  bool _loading = true;

  String _folderNameForFile(File file) {
    final segments = file.path.split(Platform.pathSeparator);
    final recordingsIndex = segments.lastIndexOf('recordings');

    if (recordingsIndex >= 0 && recordingsIndex + 1 < segments.length) {
      return segments[recordingsIndex + 1];
    }

    return 'Unknown date';
  }

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  Future<void> _loadRecordings() async {
    setState(() => _loading = true);
    final files = await RecordingService.getSavedRecordings();
    setState(() {
      _recordings = files;
      _loading = false;
    });
  }

  Future<void> _deleteRecording(File file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Recording?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await RecordingService.cleanupAfterDeletion(file);
        if (!mounted) return;  // ✅ FIX: Check mounted before showing snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Recording deleted')),
        );
        _loadRecordings();
      } catch (e) {
        if (!mounted) return;  // ✅ FIX: Check mounted
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Delete failed: $e')),
        );
      }
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  List<_RecordingListItem> _buildGroupedItems() {
    final items = <_RecordingListItem>[];
    String? currentFolder;

    for (final file in _recordings) {
      final folderName = _folderNameForFile(file);
      if (folderName != currentFolder) {
        currentFolder = folderName;
        items.add(_RecordingHeaderItem(folderName));
      }
      items.add(_RecordingFileItem(file));
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final groupedItems = _buildGroupedItems();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Recordings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRecordings,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _recordings.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.videocam_off, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'No recordings yet',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Trigger SOS to start recording',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: groupedItems.length,
                  itemBuilder: (context, index) {
                    final item = groupedItems[index];
                    if (item is _RecordingHeaderItem) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                        child: Text(
                          item.folderName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }

                    final file = (item as _RecordingFileItem).file;
                    final stat = file.statSync();
                    final date = stat.modified;
                    final size = stat.size;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.red,
                          child: Icon(Icons.videocam, color: Colors.white),
                        ),
                        title: const Text(  // ✅ FIX: Remove dynamic Text()
                          'SOS Recording',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(DateFormat('MMM dd, yyyy - hh:mm a').format(date)),
                            const SizedBox(height: 2),
                            Text(
                              _formatFileSize(size),
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.play_arrow, color: Colors.blue),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => VideoPlayerScreen(file: file),
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteRecording(file),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

abstract class _RecordingListItem {}

class _RecordingHeaderItem extends _RecordingListItem {
  final String folderName;

  _RecordingHeaderItem(this.folderName);
}

class _RecordingFileItem extends _RecordingListItem {
  final File file;

  _RecordingFileItem(this.file);
}

// ✅ Video Player Screen
class VideoPlayerScreen extends StatefulWidget {
  final File file;

  const VideoPlayerScreen({super.key, required this.file});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      _controller = VideoPlayerController.file(widget.file);
      await _controller.initialize();
      await _controller.setLooping(false);
      
      if (!mounted) return;  // ✅ FIX: Check mounted
      setState(() => _initialized = true);
      _controller.play();
    } catch (e) {
      if (!mounted) return;  // ✅ FIX: Check mounted
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Play Recording'),
        backgroundColor: Colors.black,
      ),
      body: Center(
        child: _error != null
            ? Text(
                'Error: $_error',
                style: const TextStyle(color: Colors.white),
              )
            : !_initialized
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: VideoPlayer(_controller),
                      ),
                      const SizedBox(height: 20),
                      VideoProgressIndicator(
                        _controller,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: Colors.red,
                          bufferedColor: Colors.grey,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: Icon(
                              _controller.value.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              size: 40,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              setState(() {
                                _controller.value.isPlaying
                                    ? _controller.pause()
                                    : _controller.play();
                              });
                            },
                          ),
                          const SizedBox(width: 20),
                          IconButton(
                            icon: const Icon(
                              Icons.replay,
                              size: 40,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              _controller.seekTo(Duration.zero);
                              _controller.play();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${_formatDuration(_controller.value.position)} / ${_formatDuration(_controller.value.duration)}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    
    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}
