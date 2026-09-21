import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

const defaultApiUrl = String.fromEnvironment(
  'TRAILWATCH_API_URL',
  defaultValue: 'https://trailwatch.dilanp.duckdns.org',
);

void main() => runApp(const TrailWatchApp());

class TrailWatchApp extends StatefulWidget {
  const TrailWatchApp({super.key});

  @override
  State<TrailWatchApp> createState() => _TrailWatchAppState();
}

class _TrailWatchAppState extends State<TrailWatchApp> {
  TripSession? _session;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('active_trip');
    if (saved != null) {
      try {
        _session = TripSession.fromJson(jsonDecode(saved));
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setSession(TripSession? session) async {
    final prefs = await SharedPreferences.getInstance();
    if (session == null) {
      await prefs.remove('active_trip');
    } else {
      await prefs.setString('active_trip', jsonEncode(session.toJson()));
    }
    if (mounted) setState(() => _session = session);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrailWatch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF17422E),
          brightness: Brightness.light,
          background: const Color(0xFFF2F4EF),
        ),
        scaffoldBackgroundColor: const Color(0xFFF2F4EF),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD7DFD7)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD7DFD7)),
          ),
        ),
      ),
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : VisitorShell(
              key: ValueKey(_session?.id ?? 'visitor'),
              session: _session,
              onJoined: _setSession,
              onFinished: () => _setSession(null),
            ),
    );
  }
}

class TripSession {
  const TripSession({
    required this.id,
    required this.code,
    required this.token,
    required this.visitorName,
    required this.routeName,
    required this.expectedReturnAt,
    required this.apiUrl,
  });

  final String id;
  final String code;
  final String token;
  final String visitorName;
  final String routeName;
  final DateTime expectedReturnAt;
  final String apiUrl;

  factory TripSession.fromJson(Map<String, dynamic> json) => TripSession(
        id: json['id'],
        code: json['code'],
        token: json['token'],
        visitorName: json['visitorName'],
        routeName: json['routeName'],
        expectedReturnAt: DateTime.parse(json['expectedReturnAt']),
        apiUrl: json['apiUrl'],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'token': token,
        'visitorName': visitorName,
        'routeName': routeName,
        'expectedReturnAt': expectedReturnAt.toIso8601String(),
        'apiUrl': apiUrl,
      };
}

class VisitorShell extends StatefulWidget {
  const VisitorShell({
    super.key,
    required this.session,
    required this.onJoined,
    required this.onFinished,
  });

  final TripSession? session;
  final Future<void> Function(TripSession session) onJoined;
  final Future<void> Function() onFinished;

  @override
  State<VisitorShell> createState() => _VisitorShellState();
}

class _VisitorShellState extends State<VisitorShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          const ParkNavigatorScreen(),
          if (widget.session == null)
            JoinTripScreen(onJoined: widget.onJoined)
          else
            TrackingScreen(
              session: widget.session!,
              onFinished: widget.onFinished,
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Navigate',
          ),
          NavigationDestination(
            icon: Icon(widget.session == null
                ? Icons.qr_code_scanner
                : Icons.hiking_outlined),
            selectedIcon:
                Icon(widget.session == null ? Icons.qr_code_2 : Icons.hiking),
            label: widget.session == null ? 'Ticket' : 'Active trip',
          ),
        ],
      ),
    );
  }
}

class ParkArtifact {
  const ParkArtifact({
    required this.name,
    required this.description,
    required this.position,
    required this.icon,
  });

  final String name;
  final String description;
  final LatLng position;
  final IconData icon;
}

class ParkNavigatorScreen extends StatefulWidget {
  const ParkNavigatorScreen({super.key});

  @override
  State<ParkNavigatorScreen> createState() => _ParkNavigatorScreenState();
}

class _ParkNavigatorScreenState extends State<ParkNavigatorScreen> {
  static const LatLng _parkCenter = LatLng(6.6807756, 79.9257330);
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  LatLng? _currentLocation;
  bool _locating = false;
  bool _standardRoute = true;
  int? _startIndex;
  int _destinationIndex = 6;
  String _query = '';

  static LatLng _offset(double eastMeters, double northMeters) {
    final latitude = _parkCenter.latitude + northMeters / 111320;
    final longitude = _parkCenter.longitude +
        eastMeters / (111320 * math.cos(_parkCenter.latitude * math.pi / 180));
    return LatLng(latitude, longitude);
  }

  late final List<ParkArtifact> _artifacts = [
    ParkArtifact(
      name: 'Gate House',
      description: 'Point A · visitor entrance',
      position: _offset(-720, -560),
      icon: Icons.door_front_door_outlined,
    ),
    ParkArtifact(
      name: 'Clay House',
      description: 'Traditional clay-building exhibit',
      position: _offset(-460, -350),
      icon: Icons.cottage_outlined,
    ),
    ParkArtifact(
      name: 'Mendis Manor',
      description: 'Mock restored manor house',
      position: _offset(-210, -120),
      icon: Icons.account_balance_outlined,
    ),
    ParkArtifact(
      name: 'Courtyard House',
      description: 'Open courtyard artifact',
      position: _offset(60, 10),
      icon: Icons.home_work_outlined,
    ),
    ParkArtifact(
      name: 'Garden House',
      description: 'House and heritage garden',
      position: _offset(230, 260),
      icon: Icons.yard_outlined,
    ),
    ParkArtifact(
      name: 'Veranda House',
      description: 'Colonial veranda exhibit',
      position: _offset(470, 430),
      icon: Icons.house_siding_outlined,
    ),
    ParkArtifact(
      name: 'Archive House',
      description: 'Point B · destination gallery',
      position: _offset(690, 700),
      icon: Icons.museum_outlined,
    ),
  ];

  late final List<LatLng> _boundary = [
    _offset(-1050, -620),
    _offset(-1180, 120),
    _offset(-760, 900),
    _offset(-80, 1170),
    _offset(820, 940),
    _offset(1180, 260),
    _offset(930, -720),
    _offset(160, -1060),
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ParkArtifact> get _searchResults {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return _artifacts
        .where((artifact) => artifact.name.toLowerCase().contains(query))
        .toList();
  }

  List<LatLng> get _routePoints {
    if (_standardRoute) {
      return _artifacts.map((artifact) => artifact.position).toList();
    }
    final effectiveStart = _startIndex ?? 0;
    final low = math.min(effectiveStart, _destinationIndex);
    final high = math.max(effectiveStart, _destinationIndex);
    var points = _artifacts
        .sublist(low, high + 1)
        .map((artifact) => artifact.position)
        .toList();
    if (effectiveStart > _destinationIndex) points = points.reversed.toList();
    if (_startIndex == null && _currentLocation != null) {
      points.insert(0, _currentLocation!);
    }
    return points;
  }

  double get _routeDistanceMeters {
    final points = _routePoints;
    var distance = 0.0;
    for (var index = 1; index < points.length; index++) {
      distance += Geolocator.distanceBetween(
        points[index - 1].latitude,
        points[index - 1].longitude,
        points[index].latitude,
        points[index].longitude,
      );
    }
    return distance;
  }

  String get _distanceLabel {
    final distance = _routeDistanceMeters;
    return distance >= 1000
        ? '${(distance / 1000).toStringAsFixed(1)} km'
        : '${distance.round()} m';
  }

  String get _durationLabel {
    final minutes = math.max(1, (_routeDistanceMeters / 75).round());
    return '$minutes min walk';
  }

  String get _routeTitle {
    if (_standardRoute) return 'Standard route · A to B';
    final start = _startIndex == null
        ? (_currentLocation == null ? 'Gate House' : 'Your location')
        : _artifacts[_startIndex!].name;
    return '$start → ${_artifacts[_destinationIndex].name}';
  }

  Future<void> _loadCurrentLocation({bool moveMap = false}) async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Location services are off');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission was not granted');
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      final point = LatLng(position.latitude, position.longitude);
      setState(() => _currentLocation = point);
      if (moveMap) _mapController.move(point, 17);
    } catch (error) {
      if (moveMap && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _selectArtifact(ParkArtifact artifact) {
    final index = _artifacts.indexOf(artifact);
    setState(() {
      _standardRoute = false;
      _startIndex = null;
      _destinationIndex = index;
      _query = '';
      _searchController.clear();
    });
    FocusScope.of(context).unfocus();
    _mapController.move(artifact.position, 17);
  }

  void _showDirections() {
    var draftStart = _startIndex ?? -1;
    var draftDestination = _destinationIndex;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            4,
            22,
            22 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Artifact directions',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose two park artifacts, or begin from your GPS position.',
                style: TextStyle(color: Color(0xFF657269)),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<int>(
                value: draftStart,
                decoration: const InputDecoration(
                  labelText: 'Start',
                  prefixIcon: Icon(Icons.trip_origin),
                ),
                items: [
                  const DropdownMenuItem(
                    value: -1,
                    child: Text('My location'),
                  ),
                  ...List.generate(
                    _artifacts.length,
                    (index) => DropdownMenuItem(
                      value: index,
                      child: Text(_artifacts[index].name),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    setSheetState(() => draftStart = value ?? -1),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: draftDestination,
                decoration: const InputDecoration(
                  labelText: 'Destination',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
                items: List.generate(
                  _artifacts.length,
                  (index) => DropdownMenuItem(
                    value: index,
                    child: Text(_artifacts[index].name),
                  ),
                ),
                onChanged: (value) => setSheetState(
                    () => draftDestination = value ?? _destinationIndex),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _standardRoute = false;
                    _startIndex = draftStart == -1 ? null : draftStart;
                    _destinationIndex = draftDestination;
                  });
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.directions_walk),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Show directions'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStandardRoute() {
    setState(() {
      _standardRoute = true;
      _startIndex = 0;
      _destinationIndex = _artifacts.length - 1;
    });
    _mapController.move(_parkCenter, 14.4);
  }

  Marker _artifactMarker(ParkArtifact artifact, int index) {
    final isStart = index == 0;
    final isDestination = index == _artifacts.length - 1;
    final selected = !_standardRoute && index == _destinationIndex;
    return Marker(
      point: artifact.position,
      width: 112,
      height: 66,
      builder: (context) => GestureDetector(
        onTap: () => _selectArtifact(artifact),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: isDestination || selected ? 34 : 30,
              height: isDestination || selected ? 34 : 30,
              decoration: BoxDecoration(
                color: isDestination || selected
                    ? const Color(0xFFF97316)
                    : isStart
                        ? const Color(0xFF17422E)
                        : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 5),
                ],
              ),
              child: isStart || isDestination
                  ? Center(
                      child: Text(
                        isStart ? 'A' : 'B',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    )
                  : Icon(artifact.icon,
                      size: 17, color: const Color(0xFF17422E)),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.94),
                borderRadius: BorderRadius.circular(7),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 3),
                ],
              ),
              child: Text(
                artifact.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final routePoints = _routePoints;
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: _parkCenter,
              zoom: 14.4,
              minZoom: 12,
              maxZoom: 19,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.trailwatch.trailwatch_mobile',
              ),
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: _boundary,
                    isFilled: true,
                    color: const Color(0x2642A66D),
                    borderColor: const Color(0xFF1F6A43),
                    borderStrokeWidth: 3,
                  ),
                ],
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: routePoints,
                    strokeWidth: 9,
                    color: Colors.white.withOpacity(.92),
                  ),
                  Polyline(
                    points: routePoints,
                    strokeWidth: 5,
                    color: const Color(0xFFF97316),
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  ...List.generate(
                    _artifacts.length,
                    (index) => _artifactMarker(_artifacts[index], index),
                  ),
                  if (_currentLocation != null)
                    Marker(
                      point: _currentLocation!,
                      width: 34,
                      height: 34,
                      builder: (context) => Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 7),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Column(
                  children: [
                    Material(
                      elevation: 5,
                      shadowColor: Colors.black26,
                      borderRadius: BorderRadius.circular(18),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _query = value),
                        decoration: InputDecoration(
                          hintText: 'Search park artifacts',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _query.isEmpty
                              ? const Icon(Icons.house_outlined)
                              : IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _query = '');
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                    if (_query.isNotEmpty)
                      Material(
                        elevation: 6,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(16),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 260),
                          child: _searchResults.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(18),
                                  child: Text('No artifact found'),
                                )
                              : ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: _searchResults.length,
                                  itemBuilder: (context, index) {
                                    final artifact = _searchResults[index];
                                    return ListTile(
                                      leading: Icon(artifact.icon),
                                      title: Text(artifact.name),
                                      subtitle: Text(artifact.description),
                                      trailing: const Icon(Icons.directions),
                                      onTap: () => _selectArtifact(artifact),
                                    );
                                  },
                                ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 14,
            bottom: 158,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'park-home',
                  onPressed: _showStandardRoute,
                  tooltip: 'Show the whole park',
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF17422E),
                  child: const Icon(Icons.park_outlined),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'my-location',
                  onPressed: _locating
                      ? null
                      : () => _loadCurrentLocation(moveMap: true),
                  tooltip: 'My location',
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF2563EB),
                  child: _locating
                      ? const Padding(
                          padding: EdgeInsets.all(11),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: SafeArea(
              top: false,
              child: Material(
                elevation: 8,
                shadowColor: Colors.black38,
                borderRadius: BorderRadius.circular(18),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 13, 10, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 43,
                        height: 43,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE8D5),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(Icons.directions_walk,
                            color: Color(0xFFE45D0B)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _routeTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '$_distanceLabel · $_durationLabel · mock trail',
                              style: const TextStyle(
                                color: Color(0xFF657269),
                                fontSize: 12,
                              ),
                            ),
                            if (!_standardRoute)
                              GestureDetector(
                                onTap: _showStandardRoute,
                                child: const Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Restore standard route',
                                    style: TextStyle(
                                      color: Color(0xFF23744A),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton.filled(
                        onPressed: _showDirections,
                        tooltip: 'Choose route',
                        icon: const Icon(Icons.alt_route),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 16,
            top: 84,
            child: SafeArea(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xE617422E),
                    borderRadius: BorderRadius.all(Radius.circular(9)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    child: Text(
                      'Mendis Imagine Park · mock zone',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TrailWatchApi {
  TrailWatchApi(this.baseUrl);
  final String baseUrl;

  Uri _uri(String path) =>
      Uri.parse('${baseUrl.replaceAll(RegExp(r'/$'), '')}$path');

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final response = await http
        .post(
          _uri(path),
          headers: {'content-type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['error'] ?? 'TrailWatch request failed');
    }
    return data;
  }

  Future<TripSession> join(String code) async {
    final data = await _post('/api/mobile/join', {'code': code});
    final trip = data['trip'];
    return TripSession(
      id: trip['id'],
      code: trip['code'],
      token: trip['accessToken'],
      visitorName: trip['visitorName'],
      routeName: trip['routeName'],
      expectedReturnAt: DateTime.parse(trip['expectedReturnAt']),
      apiUrl: baseUrl,
    );
  }

  Future<void> sendLocation(TripSession trip, Map<String, dynamic> location) =>
      _post('/api/mobile/location',
          {...location, 'tripId': trip.id, 'token': trip.token});

  Future<void> sendSos(TripSession trip) => _post('/api/mobile/sos', {
        'tripId': trip.id,
        'token': trip.token,
        'message': 'Visitor requested emergency assistance from the mobile app',
      });

  Future<void> complete(TripSession trip) => _post('/api/mobile/complete', {
        'tripId': trip.id,
        'token': trip.token,
      });
}

class JoinTripScreen extends StatefulWidget {
  const JoinTripScreen({super.key, required this.onJoined});
  final Future<void> Function(TripSession session) onJoined;

  @override
  State<JoinTripScreen> createState() => _JoinTripScreenState();
}

class _JoinTripScreenState extends State<JoinTripScreen> {
  final _code = TextEditingController();
  final _apiUrl = TextEditingController(text: defaultApiUrl);
  bool _busy = false;
  bool _showSettings = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _apiUrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    FocusScope.of(context).unfocus();
    final code = _code.text.trim().toUpperCase();
    if (code.isEmpty || _apiUrl.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await TrailWatchApi(_apiUrl.text.trim()).join(code);
      await widget.onJoined(session);
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanTicket() async {
    final scannedCode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const TicketScannerScreen()),
    );
    if (scannedCode == null || !mounted) return;
    _code.text = scannedCode;
    await _join();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const BrandHeader(),
                    const SizedBox(height: 52),
                    Text('Start your trip',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1)),
                    const SizedBox(height: 8),
                    Text(
                        'Enter the ticket code from the park counter. Location sharing starts only after you join.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: const Color(0xFF657269), height: 1.45)),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _code,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      decoration: const InputDecoration(
                          labelText: 'Trip code',
                          hintText: 'TW-AB12CD34',
                          prefixIcon: Icon(Icons.confirmation_number_outlined)),
                      onSubmitted: (_) => _join(),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _scanTicket,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 13),
                        child: Text('Scan ticket QR'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton.icon(
                        onPressed: () =>
                            setState(() => _showSettings = !_showSettings),
                        icon: const Icon(Icons.settings_outlined, size: 19),
                        label: Text(_showSettings
                            ? 'Hide server settings'
                            : 'Server settings')),
                    if (_showSettings) ...[
                      const SizedBox(height: 8),
                      TextField(
                          controller: _apiUrl,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: const InputDecoration(
                              labelText: 'TrailWatch server URL',
                              helperText:
                                  'The hosted TrailWatch server is used by default')),
                    ],
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(_error!,
                              style:
                                  const TextStyle(color: Color(0xFFB72C22)))),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                        onPressed: _busy ? null : _join,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.arrow_forward),
                        label: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 15),
                            child: Text('Join trip'))),
                    const SizedBox(height: 34),
                    const SafetyNote(),
                  ]),
            ),
          ),
        ),
      ),
    );
  }
}

class TicketScannerScreen extends StatefulWidget {
  const TicketScannerScreen({super.key});

  @override
  State<TicketScannerScreen> createState() => _TicketScannerScreenState();
}

class _TicketScannerScreenState extends State<TicketScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue?.trim().toUpperCase();
    if (raw == null) return;
    final match = RegExp(r'TW-[A-Z0-9]{8}').firstMatch(raw);
    if (match == null) return;
    _handled = true;
    Navigator.of(context).pop(match.group(0));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan trail ticket'),
        actions: [
          IconButton(
            onPressed: _controller.toggleTorch,
            tooltip: 'Toggle flashlight',
            icon: const Icon(Icons.flashlight_on_outlined),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              'Point the camera at the QR code shown on the ranger dashboard.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class TrackingScreen extends StatefulWidget {
  const TrackingScreen(
      {super.key, required this.session, required this.onFinished});
  final TripSession session;
  final Future<void> Function() onFinished;

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  Timer? _timer;
  DateTime? _lastSent;
  String _status = 'Preparing GPS…';
  bool _sending = false;
  bool _sosSent = false;
  int _queued = 0;

  TrailWatchApi get _api => TrailWatchApi(widget.session.apiUrl);

  @override
  void initState() {
    super.initState();
    _startTracking();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) {
        setState(
            () => _status = 'Turn on location services to share your position');
      }
      return false;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(
            () => _status = 'Location permission is required for this trip');
      }
      return false;
    }
    return true;
  }

  Future<void> _startTracking() async {
    if (!await _ensurePermission()) return;
    await _sendCurrentLocation();
    _timer = Timer.periodic(
        const Duration(minutes: 1), (_) => _sendCurrentLocation());
  }

  Future<List<Map<String, dynamic>>> _readQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('location_queue') ?? [];
    return raw
        .map((item) => Map<String, dynamic>.from(jsonDecode(item)))
        .toList();
  }

  Future<void> _writeQueue(List<Map<String, dynamic>> queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('location_queue', queue.map(jsonEncode).toList());
    if (mounted) setState(() => _queued = queue.length);
  }

  Future<void> _flushQueue() async {
    final queue = await _readQueue();
    final remaining = <Map<String, dynamic>>[];
    for (final item in queue) {
      try {
        await _api.sendLocation(widget.session, item);
      } catch (_) {
        remaining.add(item);
      }
    }
    await _writeQueue(remaining);
  }

  Future<void> _sendCurrentLocation() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _status = 'Getting current location…';
    });
    try {
      final position = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high)
          .timeout(const Duration(seconds: 25));
      final battery = await Battery().batteryLevel;
      final update = <String, dynamic>{
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracyMeters': position.accuracy,
        'altitudeMeters': position.altitude,
        'batteryPercent': battery,
        'recordedAt': position.timestamp.toUtc().toIso8601String(),
      };
      try {
        await _flushQueue();
        await _api.sendLocation(widget.session, update);
        if (mounted) {
          setState(() {
            _lastSent = DateTime.now();
            _status = 'Location shared with park staff';
          });
        }
      } catch (_) {
        final queue = await _readQueue();
        queue.add(update);
        await _writeQueue(queue.take(100).toList());
        if (mounted) {
          setState(() => _status = 'Offline — location saved and will retry');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _status = 'Could not get a GPS position. Tap to retry.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendSos() async {
    final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                    title: const Text('Send emergency alert?'),
                    content: const Text(
                        'Park staff will see an SOS for this trip. If possible, also call the local emergency number.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFB72C22)),
                          child: const Text('Send SOS'))
                    ])) ??
        false;
    if (!confirmed) return;
    try {
      await _sendCurrentLocation();
      await _api.sendSos(widget.session);
      if (mounted) setState(() => _sosSent = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('SOS could not be sent. Call emergency services now.')));
      }
    }
  }

  Future<void> _finish() async {
    final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                    title: const Text('Finish this trip?'),
                    content: const Text(
                        'Only finish when you are safely back at the park counter or exit.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Not yet')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('I am safely back'))
                    ])) ??
        false;
    if (!confirmed) return;
    try {
      await _api.complete(widget.session);
      await widget.onFinished();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not finish the trip. Check your connection and retry.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining =
        widget.session.expectedReturnAt.difference(DateTime.now());
    final overdue = remaining.isNegative;
    final timeText = overdue
        ? '${remaining.inMinutes.abs()} min overdue'
        : '${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m remaining';
    return Scaffold(
      body: SafeArea(
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const BrandHeader(),
                    const SizedBox(height: 28),
                    Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                            color: const Color(0xFF17422E),
                            borderRadius: BorderRadius.circular(22)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('ACTIVE TRIP',
                                        style: TextStyle(
                                            color: Color(0xFFB9D8C4),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1)),
                                    Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                            color: Colors.white12,
                                            borderRadius:
                                                BorderRadius.circular(30)),
                                        child: Text(widget.session.code,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12)))
                                  ]),
                              const SizedBox(height: 22),
                              Text(widget.session.routeName,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 25,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -.7)),
                              const SizedBox(height: 7),
                              Text('${widget.session.visitorName} · $timeText',
                                  style: TextStyle(
                                      color: overdue
                                          ? const Color(0xFFFFC0B9)
                                          : const Color(0xFFD7E5DB),
                                      fontSize: 14))
                            ])),
                    const SizedBox(height: 16),
                    Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: const Color(0xFFD7DFD7)),
                            borderRadius: BorderRadius.circular(17)),
                        child: Row(children: [
                          Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                  color: const Color(0xFFE1F2E7),
                                  borderRadius: BorderRadius.circular(13)),
                              child: Icon(
                                  _sending
                                      ? Icons.my_location
                                      : Icons.location_on_outlined,
                                  color: const Color(0xFF23744A))),
                          const SizedBox(width: 14),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(_status,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                Text(
                                    _lastSent == null
                                        ? 'Waiting for first update'
                                        : 'Last sent at ${TimeOfDay.fromDateTime(_lastSent!).format(context)}${_queued > 0 ? ' · $_queued queued' : ''}',
                                    style: const TextStyle(
                                        color: Color(0xFF6C786F), fontSize: 12))
                              ])),
                          IconButton(
                              onPressed: _sending ? null : _sendCurrentLocation,
                              tooltip: 'Send location now',
                              icon: const Icon(Icons.refresh))
                        ])),
                    const SizedBox(height: 22),
                    if (_sosSent)
                      Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                              color: const Color(0xFFFBE3E0),
                              borderRadius: BorderRadius.circular(14)),
                          child: const Row(children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Color(0xFFB72C22)),
                            SizedBox(width: 12),
                            Expanded(
                                child: Text(
                                    'SOS sent. Stay where you are if it is safe and follow local emergency instructions.',
                                    style: TextStyle(
                                        color: Color(0xFF84231C),
                                        fontWeight: FontWeight.w600)))
                          ])),
                    if (_sosSent) const SizedBox(height: 16),
                    OutlinedButton.icon(
                        onPressed: _sendSos,
                        style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFB72C22),
                            side: const BorderSide(color: Color(0xFFD8948D)),
                            padding: const EdgeInsets.symmetric(vertical: 17)),
                        icon: const Icon(Icons.sos),
                        label: Text(
                            _sosSent ? 'Send SOS again' : 'Emergency SOS')),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                        onPressed: _finish,
                        style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 17)),
                        icon: const Icon(Icons.flag_outlined),
                        label: const Text('Finish trip safely')),
                    const SizedBox(height: 28),
                    const SafetyNote(),
                  ]))),
    );
  }
}

class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: const Color(0xFF17422E),
                borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.explore_outlined, color: Colors.white)),
        const SizedBox(width: 12),
        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('TrailWatch',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.3)),
          Text('Visitor safety',
              style: TextStyle(fontSize: 12, color: Color(0xFF748078)))
        ])
      ]);
}

class SafetyNote extends StatelessWidget {
  const SafetyNote({super.key});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFFE8ECE5),
          borderRadius: BorderRadius.circular(14)),
      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 20, color: Color(0xFF536158)),
        SizedBox(width: 11),
        Expanded(
            child: Text(
                'Location sharing is a safety aid, not a rescue guarantee. Follow park instructions and carry the recommended equipment.',
                style: TextStyle(
                    color: Color(0xFF536158), fontSize: 13, height: 1.45)))
      ]));
}
