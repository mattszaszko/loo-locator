import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:exif_reader/exif_reader.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';
import 'loo_svg_icon.dart';
import 'onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  try {
    await GoogleSignIn.instance.initialize();
  } catch (e, st) {
    debugPrint('GoogleSignIn.initialize failed: $e\n$st');
  }
  runApp(const LooLocatorApp());
}

class LooLocatorApp extends StatelessWidget {
  const LooLocatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    const surface = Color(0xFF121212);
    const accent = Color(0xFFFFC107);
    const text = Colors.white;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Loo Locator',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
          primary: accent,
          secondary: accent,
          surface: surface,
          onPrimary: Colors.black,
          onSecondary: Colors.black,
          onSurface: text,
        ),
        scaffoldBackgroundColor: surface,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: text),
          bodyMedium: TextStyle(color: text),
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return const MainShell();
        }
        return const OnboardingScreen();
      },
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 1;
  Position? _currentPosition;
  bool _deletingLoo = false;
  MapCamera? _mapCamera;
  int? _routeDurationSec;
  Timer? _routeDebounce;
  final ImagePicker _picker = ImagePicker();
  final MapController _mapController = MapController();
  Timer? _locationRefreshTimer;
  final CollectionReference<Map<String, dynamic>> _toiletCollection =
      FirebaseFirestore.instance.collection('toilets');
  bool _mapLocationSnackShown = false;

  @override
  void initState() {
    super.initState();
    _refreshCurrentLocation().then((_) {
      if (mounted) {
        _maybePromptLocationOnMap();
      }
    });
    _locationRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) {
        return;
      }
      if (_selectedIndex != 1) {
        return;
      }
      _refreshCurrentLocation();
    });
  }

  @override
  void dispose() {
    _locationRefreshTimer?.cancel();
    _routeDebounce?.cancel();
    super.dispose();
  }

  Future<void> _refreshCurrentLocation({bool centerMap = true}) async {
    final position = await _getCurrentPositionWithPermissions();
    if (!mounted) {
      return;
    }
    setState(() => _currentPosition = position);
    if (centerMap) {
      _centerMapOnUser();
    }
  }

  Future<Position?> _getCurrentPositionWithPermissions() async {
    final isEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isEnabled) {
      return null;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      return null;
    }
    return Geolocator.getCurrentPosition();
  }

  Future<void> _maybePromptLocationOnMap() async {
    if (_mapLocationSnackShown || _selectedIndex != 1) {
      return;
    }
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      return;
    }
    _mapLocationSnackShown = true;
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final isBlockedForever = permission == LocationPermission.deniedForever;
    messenger.showSnackBar(
      SnackBar(
        content: const Text(
          'Turn on location to see the nearest loo and your position on the map.',
        ),
        action: SnackBarAction(
          label: isBlockedForever ? 'Settings' : 'Allow',
          onPressed: () async {
            if (isBlockedForever) {
              await Geolocator.openAppSettings();
            } else {
              await Geolocator.requestPermission();
            }
            if (mounted) {
              await _refreshCurrentLocation();
            }
          },
        ),
      ),
    );
  }

  void _centerMapOnUser() {
    final pos = _currentPosition;
    if (pos == null) {
      return;
    }
    if (_selectedIndex != 1) {
      return;
    }
    _mapController.move(LatLng(pos.latitude, pos.longitude), 16);
  }

  void _onNavTap(int index) {
    if (index == 2) {
      _startAddLooFromCamera();
      return;
    }
    setState(() => _selectedIndex = index);
    if (index == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _centerMapOnUser();
        _maybePromptLocationOnMap();
      });
    }
  }

  Future<void> _startAddLooFromCamera() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: null,
        requestFullMetadata: true,
      );
      if (!mounted || picked == null) {
        return;
      }
      final bytes = await picked.readAsBytes();
      final metadata = await _extractMetadata(bytes);
      final devicePos = await _getCurrentPositionWithPermissions();
      final deviceLatLng = devicePos == null
          ? null
          : LatLng(devicePos.latitude, devicePos.longitude);

      LatLng? location = metadata.latLng;
      final usedExif = location != null;
      if (location == null) {
        location = deviceLatLng;
        if (deviceLatLng != null) {
          _showMessage(
            "Couldn't read location from the photo. Using your current location instead.",
          );
        }
      }
      if (location == null) {
        _showMessage(
          'Could not determine location. Enable GPS and try again.',
        );
        return;
      }

      final timestamp = metadata.timestamp ?? DateTime.now();
      if (!mounted) {
        return;
      }

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF1B1B1B),
        builder: (sheetContext) {
          return _PostLooConfirmSheet(
            imageBytes: bytes,
            usedExifLocation: usedExif,
            onCancel: () => Navigator.pop(sheetContext),
            onUpload: () => _uploadLooAfterConfirm(
              bytes: bytes,
              location: location!,
              timestamp: timestamp,
              sheetContext: sheetContext,
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('Camera / prepare loo failed: $e');
      if (mounted) {
        _showMessage('Could not open camera. Please try again.');
      }
    }
  }

  Future<void> _uploadLooAfterConfirm({
    required Uint8List bytes,
    required LatLng location,
    required DateTime timestamp,
    required BuildContext sheetContext,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('You need to be logged in to post a loo.');
      return;
    }
    try {
      final uploadBytes = _compressForUpload(bytes);
      final now = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'toilets/$now.jpg';
      final storageRef = FirebaseStorage.instance.ref().child(storagePath);
      await storageRef.putData(
        uploadBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final imageUrl = await storageRef.getDownloadURL();
      await _toiletCollection.add({
        'imageUrl': imageUrl,
        'storagePath': storagePath,
        'location': GeoPoint(location.latitude, location.longitude),
        'timestamp': Timestamp.fromDate(timestamp),
        'createdBy': user.uid,
      });
      if (sheetContext.mounted) {
        Navigator.pop(sheetContext);
      }
      if (mounted) {
        setState(() => _selectedIndex = 1);
        _showMessage('Loo posted successfully.');
        await _refreshCurrentLocation();
      }
    } on FirebaseException catch (e) {
      debugPrint('FirebaseException during post loo: ${e.code} ${e.message}');
      if (mounted) {
        _showMessage(
          'Upload failed: ${e.code}${e.message == null ? '' : ' — ${e.message}'}',
        );
      }
    } catch (e) {
      debugPrint('Unknown error during post loo: $e');
      if (mounted) {
        _showMessage('Failed to post loo. Please try again.');
      }
    }
  }

  Uint8List _compressForUpload(Uint8List originalBytes) {
    // EXIF is already read from originalBytes; we can now resize/compress
    // aggressively for upload size.
    try {
      final decoded = img.decodeImage(originalBytes);
      if (decoded == null) {
        return originalBytes;
      }

      // Resize to a sane max dimension for mobile uploads.
      const maxDim = 1280;
      final needsResize = decoded.width > maxDim || decoded.height > maxDim;
      final resized = needsResize
          ? img.copyResize(
              decoded,
              width: decoded.width >= decoded.height ? maxDim : null,
              height: decoded.height > decoded.width ? maxDim : null,
              interpolation: img.Interpolation.average,
            )
          : decoded;

      // Encode as JPEG with fairly low quality for bandwidth.
      const quality = 35;
      final jpg = img.encodeJpg(resized, quality: quality);
      // Only keep compressed if it actually reduces size.
      if (jpg.lengthInBytes > 0 && jpg.lengthInBytes < originalBytes.length) {
        return Uint8List.fromList(jpg);
      }
      return originalBytes;
    } catch (e) {
      debugPrint('Image compression failed, uploading original: $e');
      return originalBytes;
    }
  }

  Future<_ExtractedMetadata> _extractMetadata(Uint8List bytes) async {
    try {
      final exifData = await readExifFromBytes(bytes);
      final tags = exifData.tags;
      final latTag = tags['GPS GPSLatitude'];
      final latRefTag = tags['GPS GPSLatitudeRef'];
      final lonTag = tags['GPS GPSLongitude'];
      final lonRefTag = tags['GPS GPSLongitudeRef'];
      LatLng? latLng;
      if (latTag != null && lonTag != null) {
        final lat = _dmsToDecimal(latTag.values.toList());
        final lon = _dmsToDecimal(lonTag.values.toList());
        if (lat != null && lon != null) {
          final latRef = latRefTag?.printable.toUpperCase() ?? 'N';
          final lonRef = lonRefTag?.printable.toUpperCase() ?? 'E';
          final normalizedLat = latRef.contains('S') ? -lat : lat;
          final normalizedLon = lonRef.contains('W') ? -lon : lon;
          final finiteLat = _finiteOrNull(normalizedLat);
          final finiteLon = _finiteOrNull(normalizedLon);
          if (finiteLat != null &&
              finiteLon != null &&
              finiteLat.abs() <= 90 &&
              finiteLon.abs() <= 180) {
            latLng = LatLng(finiteLat, finiteLon);
          } else {
            debugPrint(
              'EXIF GPS decoded to invalid coordinates: '
              'lat=$normalizedLat lon=$normalizedLon '
              '(ref: $latRef/$lonRef, raw: ${latTag.values.toList()} / ${lonTag.values.toList()})',
            );
          }
        }
      }
      if (latLng == null) {
        final gpsKeys = tags.keys
            .where((k) => k.toLowerCase().contains('gps'))
            .toList();
        debugPrint('EXIF GPS not found. Available GPS keys: $gpsKeys');
      }

      DateTime? timestamp =
          _parseExifDate(tags['EXIF DateTimeOriginal']?.printable) ??
          _parseExifDate(tags['Image DateTime']?.printable);
      return _ExtractedMetadata(latLng: latLng, timestamp: timestamp);
    } catch (_) {
      return const _ExtractedMetadata();
    }
  }

  double? _dmsToDecimal(List<dynamic> values) {
    // Most common format is [deg, min, sec]. Some encoders provide a single
    // decimal degree value; support that too.
    if (values.isEmpty) {
      return null;
    }
    if (values.length == 1) {
      final v = _toDouble(values[0]);
      return _finiteOrNull(v);
    }
    if (values.length < 3) {
      return null;
    }
    final d = _finiteOrNull(_toDouble(values[0]));
    final m = _finiteOrNull(_toDouble(values[1]));
    final s = _finiteOrNull(_toDouble(values[2]));
    if (d == null || m == null || s == null) {
      return null;
    }
    return _finiteOrNull(d + (m / 60) + (s / 3600));
  }

  double? _toDouble(dynamic value) {
    if (value is num) {
      return _finiteOrNull(value.toDouble());
    }
    if (value is Ratio) {
      // Guard against corrupt EXIF like 0 denominators.
      final d = value.toDouble();
      return _finiteOrNull(d);
    }
    final text = value.toString().trim();
    if (text.contains('/')) {
      final parts = text.split('/');
      if (parts.length == 2) {
        final n = double.tryParse(parts[0]);
        final d = double.tryParse(parts[1]);
        if (n != null && d != null && d != 0) {
          return _finiteOrNull(n / d);
        }
      }
    }
    return _finiteOrNull(double.tryParse(text));
  }

  double? _finiteOrNull(double? value) {
    if (value == null) {
      return null;
    }
    if (value.isNaN || value.isInfinite) {
      return null;
    }
    return value;
  }

  DateTime? _parseExifDate(String? printable) {
    if (printable == null || printable.isEmpty) {
      return null;
    }
    final normalized = printable.replaceFirst(':', '-').replaceFirst(':', '-');
    return DateTime.tryParse(normalized);
  }

  Future<void> _openExternalMap(LatLng location) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${location.latitude},${location.longitude}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  double _haversineDistanceKm(LatLng a, LatLng b) {
    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLon = _degToRad(b.longitude - a.longitude);
    final aa =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(a.latitude)) *
            math.cos(_degToRad(b.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(aa), math.sqrt(1 - aa));
    return earthRadiusKm * c;
  }

  double _degToRad(double degrees) => degrees * (math.pi / 180);

  void _scheduleRouteFetch(_NearestToilet? nearest) {
    _routeDebounce?.cancel();
    _routeDebounce = Timer(const Duration(milliseconds: 350), () {
      _fetchOsrmDrivingDuration(nearest);
    });
  }

  Future<void> _fetchOsrmDrivingDuration(_NearestToilet? nearest) async {
    final pos = _currentPosition;
    if (nearest == null || pos == null) {
      if (mounted) {
        setState(() => _routeDurationSec = null);
      }
      return;
    }
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${pos.longitude},${pos.latitude};'
        '${nearest.location.longitude},${nearest.location.latitude}'
        '?overview=false',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        if (mounted) {
          setState(() => _routeDurationSec = null);
        }
        return;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) {
        if (mounted) {
          setState(() => _routeDurationSec = null);
        }
        return;
      }
      final duration =
          (routes.first as Map<String, dynamic>)['duration'] as num?;
      if (duration != null && mounted) {
        setState(() => _routeDurationSec = duration.round());
      }
    } catch (e) {
      debugPrint('OSRM route request failed: $e');
      if (mounted) {
        setState(() => _routeDurationSec = null);
      }
    }
  }

  String _formatDriveDurationFromSeconds(int seconds) {
    final minutes = (seconds / 60).ceil().clamp(1, 9999);
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final rem = minutes % 60;
      return rem == 0 ? '~${hours}h' : '~${hours}h ${rem}m';
    }
    return '~${minutes}m';
  }

  /// Fallback when OSRM is unavailable (urban-ish heuristic, not straight-line).
  String _roughDriveEstimateFromKm(double km) {
    const effectiveKmh = 22.0;
    final minutes = (km / effectiveKmh * 60).ceil().clamp(1, 9999);
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final rem = minutes % 60;
      return rem == 0 ? '~${hours}h' : '~${hours}h ${rem}m';
    }
    return '~${minutes}m';
  }

  String _driveTimeLine(_NearestToilet? nearest) {
    if (nearest == null) {
      return '—';
    }
    if (_routeDurationSec != null) {
      return '${_formatDriveDurationFromSeconds(_routeDurationSec!)} drive';
    }
    return '${_roughDriveEstimateFromKm(nearest.distanceKm)} drive';
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _toiletCollection
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final toilets = docs.map(ToiletPoint.fromDoc).toList();
        final nearest = _currentPosition == null
            ? null
            : _findNearestToilet(
                user: LatLng(
                  _currentPosition!.latitude,
                  _currentPosition!.longitude,
                ),
                toilets: toilets,
              );

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          _scheduleRouteFetch(nearest);
        });

        final pages = <Widget>[
          ProfilePage(
            userEmail: FirebaseAuth.instance.currentUser?.email ?? 'Unknown',
          ),
          MapPage(
            mapController: _mapController,
            initialCenter: _currentPosition == null
                ? null
                : LatLng(
                    _currentPosition!.latitude,
                    _currentPosition!.longitude,
                  ),
            toilets: toilets,
            onMarkerTap: (toilet) => _showToiletSheet(toilet),
            onCameraChanged: (camera) {
              if (!mounted) {
                return;
              }
              setState(() => _mapCamera = camera);
            },
          ),
        ];

        return Scaffold(
          appBar: AppBar(
            title: const Text('Loo Locator'),
            centerTitle: true,
            actions: [
              IconButton(
                onPressed: () async {
                  await _refreshCurrentLocation();
                  _centerMapOnUser();
                },
                icon: const Icon(Icons.my_location),
              ),
            ],
          ),
          body: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _selectedIndex == 1
                      ? _buildMapWithNearestPanel(
                          map: pages[1],
                          nearest: nearest,
                          toilets: toilets,
                        )
                      : pages[_selectedIndex],
                ),
                if (_deletingLoo)
                  const _UploadingOverlay(
                    title: 'Deleting loo…',
                    subtitle: 'Removing photo and record.',
                  ),
              ],
            ),
          ),
          bottomNavigationBar: Material(
            color: Colors.black,
            elevation: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_selectedIndex == 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                    child: _buildNearestLooBar(nearest, toilets),
                  ),
                _BottomNav(
                  selectedIndex: _selectedIndex,
                  onTap: _onNavTap,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMapWithNearestPanel({
    required Widget map,
    required _NearestToilet? nearest,
    required List<ToiletPoint> toilets,
  }) {
    final cam = _mapCamera;
    final showQuest = cam != null &&
        nearest != null &&
        toilets.isNotEmpty &&
        !toilets.any((t) => cam.visibleBounds.contains(t.latLng));

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: map),
        if (showQuest) _buildOffScreenQuestHint(cam: cam, nearest: nearest),
      ],
    );
  }

  Widget _buildOffScreenQuestHint({
    required MapCamera cam,
    required _NearestToilet nearest,
  }) {
    final size = cam.size;
    final center = Offset(size.width / 2, size.height / 2);
    final target = cam.latLngToScreenOffset(nearest.location);
    final edge = _rayToBoxEdge(
      origin: center,
      toward: target,
      size: size,
      margin: 18,
    );
    final angle = math.atan2(target.dy - center.dy, target.dx - center.dx);
    return Positioned(
      left: edge.dx - 22,
      top: edge.dy - 22,
      child: GestureDetector(
        onTap: () => _openExternalMap(nearest.location),
        child: Transform.rotate(
          angle: angle,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black87,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.amber, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.navigation, color: Colors.amber, size: 26),
          ),
        ),
      ),
    );
  }

  String _formatDistanceToNearest(double km) {
    if (km < 1) {
      final m = (km * 1000).round();
      return '$m m';
    }
    return km < 10
        ? '${km.toStringAsFixed(2)} km'
        : '${km.toStringAsFixed(1)} km';
  }

  Widget _buildNearestLooBar(
    _NearestToilet? nearest,
    List<ToiletPoint> toilets,
  ) {
    final hasToilets = toilets.isNotEmpty;
    final hasPosition = _currentPosition != null;
    final hasTarget = nearest != null && hasToilets && hasPosition;

    String distanceTitle;
    String distanceSubtitle;
    if (!hasToilets) {
      distanceTitle = 'No loos yet';
      distanceSubtitle = 'Be the first to add one.';
    } else if (!hasPosition) {
      distanceTitle = 'Location off';
      distanceSubtitle = 'Turn on GPS to find the nearest loo.';
    } else if (nearest != null) {
      distanceTitle = _formatDistanceToNearest(nearest.distanceKm);
      distanceSubtitle = _driveTimeLine(nearest);
    } else {
      distanceTitle = '—';
      distanceSubtitle = 'Could not compute distance.';
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.55),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 12,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const LooSvgIcon(size: 20, color: Colors.amber),
                      const SizedBox(width: 6),
                      const Text(
                        'Nearest loo',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          distanceTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        tooltip: 'Refresh location & drive time',
                        onPressed: hasToilets
                            ? () => _refreshCurrentLocation(centerMap: false)
                            : null,
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Colors.amber,
                          size: 26,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    distanceSubtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 88,
              height: 88,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed:
                    hasTarget ? () => _openExternalMap(nearest.location) : null,
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.navigation_rounded, size: 32),
                    SizedBox(height: 2),
                    Text(
                      'GO',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Ray from [origin] toward [toward], clamped to an inset rectangle of [size].
  Offset _rayToBoxEdge({
    required Offset origin,
    required Offset toward,
    required Size size,
    required double margin,
  }) {
    final dx = toward.dx - origin.dx;
    final dy = toward.dy - origin.dy;
    if (dx.abs() < 0.01 && dy.abs() < 0.01) {
      return Offset(origin.dx, margin);
    }
    var tMin = double.infinity;
    void consider(double? t) {
      if (t != null && t > 0 && t < tMin) {
        tMin = t;
      }
    }
    if (dx != 0) {
      consider((margin - origin.dx) / dx);
      consider((size.width - margin - origin.dx) / dx);
    }
    if (dy != 0) {
      consider((margin - origin.dy) / dy);
      consider((size.height - margin - origin.dy) / dy);
    }
    if (!tMin.isFinite) {
      return Offset(origin.dx.clamp(margin, size.width - margin), margin);
    }
    return Offset(origin.dx + dx * tMin, origin.dy + dy * tMin);
  }

  _NearestToilet? _findNearestToilet({
    required LatLng user,
    required List<ToiletPoint> toilets,
  }) {
    _NearestToilet? nearest;
    for (final toilet in toilets) {
      final distance = _haversineDistanceKm(user, toilet.latLng);
      if (nearest == null || distance < nearest.distanceKm) {
        nearest = _NearestToilet(location: toilet.latLng, distanceKm: distance);
      }
    }
    return nearest;
  }

  void _showToiletSheet(ToiletPoint toilet) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1B1B1B),
      isScrollControlled: true,
      builder: (context) {
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        final canDelete = currentUid != null && currentUid == toilet.createdBy;
        final maxHeight = MediaQuery.of(context).size.height * 0.85;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _ToiletPhoto(toilet: toilet),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Reported: ${_formatReportedAt(toilet.timestamp)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (canDelete) ...[
                    SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) {
                              return AlertDialog(
                                title: const Text('Delete loo?'),
                                content: const Text(
                                  'This will permanently delete the loo and its photo.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              );
                            },
                          );
                          if (confirmed != true) {
                            return;
                          }
                          if (!context.mounted) {
                            return;
                          }
                          Navigator.pop(context);
                          await _deleteToilet(toilet);
                        },
                        icon: const Icon(Icons.delete),
                        label: const Text(
                          'Delete loo',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: () => _openExternalMap(toilet.latLng),
                      icon: const Icon(Icons.map),
                      label: const Text('Open in Maps'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatReportedAt(DateTime reportedAt) {
    final now = DateTime.now();
    final local = reportedAt.toLocal();

    DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

    final deltaDays = dateOnly(now).difference(dateOnly(local)).inDays;
    if (deltaDays <= 0) {
      return 'Today';
    }
    if (deltaDays == 1) {
      return 'Yesterday';
    }
    if (deltaDays <= 14) {
      return '$deltaDays days ago';
    }
    final european =
        '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
    return 'More than 2 weeks ago • $european';
  }

  Future<void> _deleteToilet(ToiletPoint toilet) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid != toilet.createdBy) {
      _showMessage('You can only delete loos you posted.');
      return;
    }
    if (_deletingLoo) {
      return;
    }
    setState(() => _deletingLoo = true);
    try {
      final storagePath = toilet.storagePath;
      if (storagePath != null && storagePath.isNotEmpty) {
        await FirebaseStorage.instance.ref().child(storagePath).delete();
      } else {
        final url = toilet.imageUrl.trim();
        if (url.startsWith('gs://')) {
          await FirebaseStorage.instance.refFromURL(url).delete();
        } else {
          // Download-token URLs aren't guaranteed to be supported by refFromURL.
          try {
            await FirebaseStorage.instance.refFromURL(url).delete();
          } catch (_) {}
        }
      }

      await _toiletCollection.doc(toilet.docId).delete();
      _showMessage('Loo deleted.');
    } on FirebaseException catch (e) {
      debugPrint('Delete loo FirebaseException: ${e.code} ${e.message}');
      _showMessage(
        'Delete failed: ${e.code}${e.message == null ? '' : ' — ${e.message}'}',
      );
    } catch (e) {
      debugPrint('Delete loo unknown error: $e');
      _showMessage('Delete failed. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _deletingLoo = false);
      }
    }
  }
}

class _PostLooConfirmSheet extends StatefulWidget {
  const _PostLooConfirmSheet({
    required this.imageBytes,
    required this.usedExifLocation,
    required this.onCancel,
    required this.onUpload,
  });

  final Uint8List imageBytes;
  final bool usedExifLocation;
  final VoidCallback onCancel;
  final Future<void> Function() onUpload;

  @override
  State<_PostLooConfirmSheet> createState() => _PostLooConfirmSheetState();
}

class _PostLooConfirmSheetState extends State<_PostLooConfirmSheet> {
  bool _uploading = false;

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.sizeOf(context).height;
    final maxHeight = screenH * 0.94;
    final previewHeight = screenH * 0.48;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Post this loo?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: previewHeight.clamp(220.0, 520.0),
                  width: double.infinity,
                  child: Image.memory(
                    widget.imageBytes,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                ),
              ),
              if (!widget.usedExifLocation) ...[
                const SizedBox(height: 10),
                const Text(
                  'Location will be saved from your device GPS (photo had no GPS).',
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _uploading
                      ? null
                      : () async {
                          setState(() => _uploading = true);
                          try {
                            await widget.onUpload();
                          } finally {
                            if (mounted) {
                              setState(() => _uploading = false);
                            }
                          }
                        },
                  icon: _uploading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload),
                  label: Text(_uploading ? 'Uploading…' : 'Upload loo'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 52,
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _uploading ? null : widget.onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFC107),
                    side: const BorderSide(color: Color(0xFFFFC107)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.userEmail});

  final String userEmail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            color: Colors.black,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.person, size: 64, color: Colors.amber),
                  const SizedBox(height: 16),
                  Text(
                    userEmail,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      icon: const Icon(Icons.logout),
                      label: const Text(
                        'Sign Out',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MapPage extends StatelessWidget {
  const MapPage({
    super.key,
    required this.mapController,
    required this.toilets,
    required this.onMarkerTap,
    this.initialCenter,
    this.onCameraChanged,
  });

  static const LatLng _utrecht = LatLng(52.0907, 5.1214);

  final MapController mapController;
  final List<ToiletPoint> toilets;
  final void Function(ToiletPoint toilet) onMarkerTap;
  final LatLng? initialCenter;
  final void Function(MapCamera camera)? onCameraChanged;

  @override
  Widget build(BuildContext context) {
    final markers = toilets
        .map(
          (toilet) => Marker(
            key: ValueKey<String>(toilet.docId),
            point: toilet.latLng,
            width: 48,
            height: 48,
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: () => onMarkerTap(toilet),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.amber, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: const Center(
                  child: LooSvgIcon(size: 28, color: Colors.amber),
                ),
              ),
            ),
          ),
        )
        .toList();

    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: initialCenter ?? _utrecht,
        initialZoom: initialCenter == null ? 13 : 16,
        onMapReady: () {
          onCameraChanged?.call(mapController.camera);
        },
        onPositionChanged: (camera, _) {
          onCameraChanged?.call(camera);
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.loo_locator',
        ),
        CurrentLocationLayer(
          alignPositionOnUpdate: AlignOnUpdate.never,
          alignDirectionOnUpdate: AlignOnUpdate.never,
          style: const LocationMarkerStyle(
            marker: DefaultLocationMarker(
              color: Colors.blueAccent,
              child: Icon(Icons.navigation, color: Colors.white),
            ),
            markerSize: Size(36, 36),
            showAccuracyCircle: true,
            headingSectorColor: Color(0x332196F3),
          ),
        ),
        MarkerClusterLayerWidget(
          options: MarkerClusterLayerOptions(
            markerChildBehavior: true,
            maxClusterRadius: 48,
            disableClusteringAtZoom: 15,
            showPolygon: false,
            size: const Size(48, 48),
            alignment: Alignment.center,
            markers: markers,
            builder: (context, clustered) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.amber, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    clustered.length.toString(),
                    style: const TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class ToiletPoint {
  const ToiletPoint({
    required this.docId,
    required this.latLng,
    required this.imageUrl,
    required this.createdBy,
    this.storagePath,
    required this.timestamp,
  });

  final String docId;
  final LatLng latLng;
  final String imageUrl;
  final String createdBy;
  final String? storagePath;
  final DateTime timestamp;

  factory ToiletPoint.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final geo = data['location'] as GeoPoint?;
    final ts = data['timestamp'] as Timestamp?;
    return ToiletPoint(
      docId: doc.id,
      latLng: LatLng(geo?.latitude ?? 0, geo?.longitude ?? 0),
      imageUrl: (data['imageUrl'] as String?) ?? '',
      createdBy: (data['createdBy'] as String?) ?? '',
      storagePath: data['storagePath'] as String?,
      timestamp: ts?.toDate() ?? DateTime.now(),
    );
  }
}

class _ToiletPhoto extends StatefulWidget {
  const _ToiletPhoto({required this.toilet});

  final ToiletPoint toilet;

  @override
  State<_ToiletPhoto> createState() => _ToiletPhotoState();
}

class _ToiletPhotoState extends State<_ToiletPhoto> {
  Future<_ResolvedToiletPhoto>? _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve(widget.toilet);
  }

  @override
  void didUpdateWidget(covariant _ToiletPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.toilet.docId != widget.toilet.docId ||
        oldWidget.toilet.imageUrl != widget.toilet.imageUrl ||
        oldWidget.toilet.storagePath != widget.toilet.storagePath) {
      _future = _resolve(widget.toilet);
    }
  }

  Future<_ResolvedToiletPhoto> _resolve(ToiletPoint toilet) async {
    final ref = _storageRefFromToilet(toilet);
    if (ref != null) {
      // On web, `getData()` goes through fetch/XHR and can fail due to
      // browser/CORS/interop issues. Loading an <img> via Image.network is
      // usually more reliable.
      if (kIsWeb) {
        final url = await ref.getDownloadURL();
        return _ResolvedToiletPhoto(url: url);
      } else {
        // Prefer authenticated Firebase SDK fetch to avoid URL/CORS/token issues.
        final bytes = await ref.getData(8 * 1024 * 1024); // 8MB cap
        if (bytes != null && bytes.isNotEmpty) {
          return _ResolvedToiletPhoto(bytes: bytes);
        }
      }
    }

    final url = _downloadUrlFromToilet(toilet);
    if (url != null) {
      return _ResolvedToiletPhoto(url: url);
    }

    throw StateError('No photo reference available.');
  }

  Reference? _storageRefFromToilet(ToiletPoint toilet) {
    final storagePath = (toilet.storagePath ?? '').trim();
    if (storagePath.isNotEmpty) {
      return FirebaseStorage.instance.ref().child(storagePath);
    }

    final url = toilet.imageUrl.trim();
    if (url.isEmpty) {
      return null;
    }
    if (url.startsWith('gs://')) {
      return FirebaseStorage.instance.refFromURL(url);
    }

    // Parse Firebase Storage download URLs:
    // https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<encodedPath>?...
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      final oIndex = segments.indexOf('o');
      if (oIndex != -1 && oIndex + 1 < segments.length) {
        final encodedPath = segments[oIndex + 1];
        final decodedPath = Uri.decodeComponent(encodedPath);
        if (decodedPath.isNotEmpty) {
          return FirebaseStorage.instance.ref().child(decodedPath);
        }
      }
    } catch (_) {}
    return null;
  }

  String? _downloadUrlFromToilet(ToiletPoint toilet) {
    final url = toilet.imageUrl.trim();
    if (url.isEmpty) {
      return null;
    }
    if (url.startsWith('gs://')) {
      return null; // prefer resolving via ref
    }
    return url;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ResolvedToiletPhoto>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ColoredBox(
            color: Colors.black26,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          debugPrint(
            'Toilet photo load failed for doc=${widget.toilet.docId} '
            'path=${widget.toilet.storagePath} url=${widget.toilet.imageUrl}: '
            '${snapshot.error}',
          );
          return const ColoredBox(
            color: Colors.black26,
            child: Center(child: Icon(Icons.broken_image, color: Colors.white)),
          );
        }
        final resolved = snapshot.data!;
        if (resolved.bytes != null) {
          return Image.memory(
            resolved.bytes!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          );
        }
        return Image.network(
          resolved.url!,
          fit: BoxFit.cover,
          // On Flutter web, the default fetch-based loader can fail with
          // statusCode 0 when the browser blocks the request (CORS/fetch).
          // For Firebase Storage download URLs, using an <img> element is the
          // most reliable approach.
          webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              return child;
            }
            return const ColoredBox(
              color: Colors.black26,
              child: Center(child: CircularProgressIndicator()),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            debugPrint(
              'Toilet photo network load failed for doc=${widget.toilet.docId} '
              'url=${resolved.url}: $error',
            );
            return const ColoredBox(
              color: Colors.black26,
              child: Center(
                child: Icon(Icons.broken_image, color: Colors.white),
              ),
            );
          },
        );
      },
    );
  }
}

class _ResolvedToiletPhoto {
  const _ResolvedToiletPhoto({this.bytes, this.url});

  final Uint8List? bytes;
  final String? url;
}

class _ExtractedMetadata {
  const _ExtractedMetadata({this.latLng, this.timestamp});

  final LatLng? latLng;
  final DateTime? timestamp;
}

class _NearestToilet {
  const _NearestToilet({required this.location, required this.distanceKm});

  final LatLng location;
  final double distanceKm;
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.selectedIndex, required this.onTap});

  static const double height = 84;

  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        height: height,
        backgroundColor: Colors.black,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
            color: isSelected ? Colors.amber : Colors.white70,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 30,
            color: isSelected ? Colors.amber : Colors.white70,
          );
        }),
      ),
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onTap,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
          NavigationDestination(icon: Icon(Icons.near_me), label: 'Find Loo'),
          NavigationDestination(
            icon: Icon(Icons.add_a_photo),
            label: 'Add Loo',
          ),
        ],
      ),
    );
  }
}

class _UploadingOverlay extends StatelessWidget {
  const _UploadingOverlay({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const ModalBarrier(dismissible: false, color: Color(0xAA000000)),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              color: Colors.black,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
