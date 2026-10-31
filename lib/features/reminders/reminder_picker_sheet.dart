import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/models/note_model.dart';
import '../../domain/services/device_services.dart';
import '../../domain/services/keep_providers.dart';

class ReminderConfigResult {
  final DateTime? reminderAt;
  final String recurrence;
  final ReminderLocation? location;
  final bool cleared;

  const ReminderConfigResult({
    this.reminderAt,
    this.recurrence = 'none',
    this.location,
    this.cleared = false,
  });
}

class ReminderPickerSheet extends ConsumerStatefulWidget {
  final DateTime? initialReminderAt;
  final String initialRecurrence;
  final ReminderLocation? initialLocation;

  const ReminderPickerSheet({
    super.key,
    this.initialReminderAt,
    this.initialRecurrence = 'none',
    this.initialLocation,
  });

  @override
  ConsumerState<ReminderPickerSheet> createState() =>
      _ReminderPickerSheetState();
}

class _ReminderPickerSheetState extends ConsumerState<ReminderPickerSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late DateTime _selectedDateTime;
  late String _recurrence;

  // Location reminder state
  final TextEditingController _placeSearchController = TextEditingController();
  final MapController _mapController = MapController();
  LatLng _selectedCoords = const LatLng(37.4220, -122.0841);
  String _placeName = 'Pinned Location';
  String _placeAddress = 'Tap on map or search a place';
  double _radiusMeters = 200.0;
  List<NominatimPlaceResult> _searchResults = [];
  bool _isSearchingPlaces = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialLocation != null ? 1 : 0,
    );
    _selectedDateTime = widget.initialReminderAt ??
        DateTime.now().add(const Duration(hours: 2));
    _recurrence = widget.initialRecurrence;

    if (widget.initialLocation != null) {
      final loc = widget.initialLocation!;
      _selectedCoords = LatLng(loc.latitude, loc.longitude);
      _placeName = loc.name;
      _placeAddress = loc.address;
      _radiusMeters = loc.radiusMeters;
      _placeSearchController.text = loc.name;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _placeSearchController.dispose();
    super.dispose();
  }

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime.isAfter(now) ? _selectedDateTime : now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date != null) {
      setState(() {
        _selectedDateTime = DateTime(
          date.year,
          date.month,
          date.day,
          _selectedDateTime.hour,
          _selectedDateTime.minute,
        );
      });
    }
  }

  Future<void> _pickCustomTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
    );
    if (time != null) {
      setState(() {
        _selectedDateTime = DateTime(
          _selectedDateTime.year,
          _selectedDateTime.month,
          _selectedDateTime.day,
          time.hour,
          time.minute,
        );
      });
    }
  }

  Future<void> _searchNominatim(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _isSearchingPlaces = true);
    final service = ref.read(keepReminderServiceProvider);
    final results = await service.searchPlaces(query);
    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _isSearchingPlaces = false;
    });
  }

  Future<void> _useCurrentGpsLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition();
        final coords = LatLng(pos.latitude, pos.longitude);
        setState(() {
          _selectedCoords = coords;
          _placeName = 'Current Location';
          _placeAddress =
              '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
        });
        _mapController.move(coords, 15);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final hasExisting =
        widget.initialReminderAt != null || widget.initialLocation != null;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.94,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  const Text(
                    'Add reminder',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (hasExisting)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop(
                          const ReminderConfigResult(cleared: true),
                        );
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Remove'),
                    ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.access_time), text: 'Time'),
                Tab(icon: Icon(Icons.place_outlined), text: 'Place (OSM)'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTimeTab(scrollController),
                  _buildPlaceTab(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTimeTab(ScrollController scrollController) {
    final now = DateTime.now();
    final laterToday = DateTime(now.year, now.month, now.day, 18, 0);
    final tomorrowMorning =
        DateTime(now.year, now.month, now.day + 1, 8, 0);
    final nextWeek = DateTime(now.year, now.month, now.day + 7, 8, 0);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Quick Presets',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (laterToday.isAfter(now))
          ListTile(
            leading: const Icon(Icons.wb_twilight_outlined),
            title: const Text('Later today'),
            trailing: const Text('6:00 PM'),
            onTap: () {
              Navigator.of(context).pop(
                ReminderConfigResult(
                  reminderAt: laterToday,
                  recurrence: _recurrence,
                ),
              );
            },
          ),
        ListTile(
          leading: const Icon(Icons.wb_sunny_outlined),
          title: const Text('Tomorrow morning'),
          trailing: const Text('8:00 AM'),
          onTap: () {
            Navigator.of(context).pop(
              ReminderConfigResult(
                reminderAt: tomorrowMorning,
                recurrence: _recurrence,
              ),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.calendar_today_outlined),
          title: const Text('Next week'),
          trailing: Text(DateFormat('EEE, 8:00 a').format(nextWeek)),
          onTap: () {
            Navigator.of(context).pop(
              ReminderConfigResult(
                reminderAt: nextWeek,
                recurrence: _recurrence,
              ),
            );
          },
        ),
        const Divider(height: 24),
        const Text(
          'Custom Date, Time & Recurrence',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickCustomDate,
                icon: const Icon(Icons.event, size: 18),
                label: Text(DateFormat('MMM d, y').format(_selectedDateTime)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickCustomTime,
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(DateFormat.jm().format(_selectedDateTime)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _recurrence,
          decoration: const InputDecoration(
            labelText: 'Repeat',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: const [
            DropdownMenuItem(value: 'none', child: Text('Does not repeat')),
            DropdownMenuItem(value: 'daily', child: Text('Daily')),
            DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
            DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _recurrence = val);
          },
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop(
              ReminderConfigResult(
                reminderAt: _selectedDateTime,
                recurrence: _recurrence,
              ),
            );
          },
          icon: const Icon(Icons.alarm_on),
          label: const Text('Save Time Reminder'),
        ),
      ],
    );
  }

  Widget _buildPlaceTab() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _placeSearchController,
                  decoration: InputDecoration(
                    hintText: 'Search address or place (OpenStreetMap)...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _isSearchingPlaces
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.arrow_forward),
                            onPressed: () =>
                                _searchNominatim(_placeSearchController.text),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                  onSubmitted: _searchNominatim,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Use current GPS location',
                onPressed: _useCurrentGpsLocation,
                icon: const Icon(Icons.my_location),
              ),
            ],
          ),
          if (_searchResults.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 130),
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final place = _searchResults[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.place, size: 18),
                    title: Text(
                      place.shortName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      place.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      final coords = LatLng(place.latitude, place.longitude);
                      setState(() {
                        _selectedCoords = coords;
                        _placeName = place.shortName;
                        _placeAddress = place.displayName;
                        _searchResults = [];
                      });
                      _mapController.move(coords, 15);
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _selectedCoords,
                  initialZoom: 14,
                  onTap: (tapPosition, point) {
                    setState(() {
                      _selectedCoords = point;
                      if (_placeSearchController.text.trim().isNotEmpty) {
                        _placeName = _placeSearchController.text.trim();
                      } else {
                        _placeName = 'Pinned Location';
                      }
                      _placeAddress =
                          '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
                    });
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.gkeep.app',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _selectedCoords,
                        width: 44,
                        height: 44,
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.redAccent,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Radius:'),
              Expanded(
                child: Slider(
                  value: _radiusMeters,
                  min: 100,
                  max: 1000,
                  divisions: 9,
                  label: '${_radiusMeters.round()}m',
                  onChanged: (v) => setState(() => _radiusMeters = v),
                ),
              ),
              Text('${_radiusMeters.round()}m'),
            ],
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop(
                  ReminderConfigResult(
                    location: ReminderLocation(
                      name: _placeName,
                      address: _placeAddress,
                      latitude: _selectedCoords.latitude,
                      longitude: _selectedCoords.longitude,
                      radiusMeters: _radiusMeters,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.pin_drop_outlined),
              label: Text('Save Place Reminder ($_placeName)'),
            ),
          ),
        ],
      ),
    );
  }
}
