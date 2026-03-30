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
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
        return const AuthPage();
      },
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _isLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });
    try {
      if (_isSignUp) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _errorText = e.message ?? 'Authentication failed');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              color: Colors.black,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _isSignUp ? 'Create Account' : 'Welcome Back',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('Email'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('Password'),
                    ),
                    const SizedBox(height: 12),
                    if (_errorText != null)
                      Text(
                        _errorText!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 54,
                      child: FilledButton(
                        onPressed: _isLoading ? null : _submit,
                        child: _isLoading
                            ? const CircularProgressIndicator()
                            : Text(_isSignUp ? 'Sign Up' : 'Log In'),
                      ),
                    ),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => setState(() => _isSignUp = !_isSignUp),
                      child: Text(
                        _isSignUp
                            ? 'Already have an account? Log in'
                            : 'Need an account? Sign up',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white54),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.amber),
      ),
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
  bool _uploading = false;
  String? _busyTitle;
  String? _busySubtitle;
  final ImagePicker _picker = ImagePicker();
  final MapController _mapController = MapController();
  final CollectionReference<Map<String, dynamic>> _toiletCollection =
      FirebaseFirestore.instance.collection('toilets');

  @override
  void initState() {
    super.initState();
    _refreshCurrentLocation();
  }

  Future<void> _refreshCurrentLocation() async {
    final position = await _getCurrentPositionWithPermissions();
    if (!mounted) {
      return;
    }
    setState(() => _currentPosition = position);
    _centerMapOnUser();
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
      _chooseAddLooSource();
      return;
    }
    setState(() => _selectedIndex = index);
    if (index == 1) {
      // Ensure the map snaps to the user's location when returning to the map.
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerMapOnUser());
    }
  }

  Future<void> _chooseAddLooSource() async {
    if (_uploading) {
      return;
    }
    final selected = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF1B1B1B),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Post a Loo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, ImageSource.camera),
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Use Camera'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.pop(context, ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Upload from Gallery'),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || selected == null) {
      return;
    }
    await _postLoo(selected);
  }

  Future<void> _postLoo(ImageSource source) async {
    if (_uploading) {
      return;
    }
    setState(() {
      _uploading = true;
      _busyTitle = 'Preparing…';
      _busySubtitle = 'Reading photo metadata.';
    });
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        // IMPORTANT: Compression/re-encoding often strips EXIF (including GPS),
        // especially on iOS and on the web. Keep original bytes when possible.
        imageQuality: null,
        requestFullMetadata: true,
      );
      if (picked == null) {
        return;
      }
      final bytes = await picked.readAsBytes();
      final _ExtractedMetadata metadata = await _extractMetadata(bytes);

      final Position? currentPos = await _getCurrentPositionWithPermissions();
      final LatLng? deviceLatLng = currentPos == null
          ? null
          : LatLng(currentPos.latitude, currentPos.longitude);

      final _PostLooConfirmation? confirmed = await _confirmPostLoo(
        imageBytes: bytes,
        exifLatLng: metadata.latLng,
        deviceLatLng: deviceLatLng,
        exifTimestamp: metadata.timestamp,
      );
      if (!mounted || confirmed == null) {
        return;
      }

      if (confirmed.latLng == null) {
        _showMessage(
          'Could not determine location. Enable GPS or use a photo with GPS.',
        );
        return;
      }
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showMessage('You need to be logged in to post a loo.');
        return;
      }

      setState(() {
        _busyTitle = 'Posting loo…';
        _busySubtitle = 'Compressing and uploading photo.';
      });
      final Uint8List uploadBytes = _compressForUpload(bytes);

      final now = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'toilets/$now.jpg';
      final storageRef = FirebaseStorage.instance.ref().child(storagePath);
      await storageRef.putData(
        uploadBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final imageUrl = await storageRef.getDownloadURL();

      setState(() {
        _busyTitle = 'Posting loo…';
        _busySubtitle = 'Saving location to database.';
      });
      await _toiletCollection.add({
        'imageUrl': imageUrl,
        'storagePath': storagePath,
        'location': GeoPoint(
          confirmed.latLng!.latitude,
          confirmed.latLng!.longitude,
        ),
        'timestamp': Timestamp.fromDate(confirmed.timestamp),
        'createdBy': user.uid,
      });
      _showMessage('Loo posted successfully.');
      await _refreshCurrentLocation();
    } on FirebaseException catch (e) {
      debugPrint('FirebaseException during post loo: ${e.code} ${e.message}');
      _showMessage(
        'Upload failed: ${e.code}${e.message == null ? '' : ' — ${e.message}'}',
      );
    } catch (e) {
      debugPrint('Unknown error during post loo: $e');
      _showMessage('Failed to post loo. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _busyTitle = null;
          _busySubtitle = null;
        });
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

  Future<_PostLooConfirmation?> _confirmPostLoo({
    required Uint8List imageBytes,
    required LatLng? exifLatLng,
    required LatLng? deviceLatLng,
    required DateTime? exifTimestamp,
  }) async {
    final hasExifGps = exifLatLng != null;
    final hasDeviceGps = deviceLatLng != null;

    final defaultSource = hasExifGps
        ? _LocationChoice.exif
        : _LocationChoice.device;
    _LocationChoice selected = defaultSource;

    final resolvedTimestamp = exifTimestamp ?? DateTime.now();

    return showModalBottomSheet<_PostLooConfirmation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1B1B1B),
      builder: (context) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (context, setModalState) {
              LatLng? chosenLatLng;
              if (selected == _LocationChoice.exif) {
                chosenLatLng = exifLatLng;
              } else {
                chosenLatLng = deviceLatLng;
              }

              return Padding(
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
                      'Confirm Loo Location',
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
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.memory(imageBytes, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _KeyValueRow(
                      label: 'Photo GPS (EXIF)',
                      value: hasExifGps ? 'Found' : 'Not found',
                      valueColor: hasExifGps
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                    ),
                    _KeyValueRow(
                      label: 'Device GPS (now)',
                      value: hasDeviceGps ? 'Available' : 'Unavailable',
                      valueColor: hasDeviceGps
                          ? Colors.greenAccent
                          : Colors.redAccent,
                    ),
                    const SizedBox(height: 10),
                    if (hasExifGps || hasDeviceGps)
                      SegmentedButton<_LocationChoice>(
                        segments: const [
                          ButtonSegment(
                            value: _LocationChoice.exif,
                            label: Text('Use Photo Location'),
                            icon: Icon(Icons.photo),
                          ),
                          ButtonSegment(
                            value: _LocationChoice.device,
                            label: Text('Use Current Location'),
                            icon: Icon(Icons.my_location),
                          ),
                        ],
                        selected: <_LocationChoice>{selected},
                        onSelectionChanged: (s) {
                          final next = s.first;
                          if (next == _LocationChoice.exif && !hasExifGps) {
                            return;
                          }
                          if (next == _LocationChoice.device && !hasDeviceGps) {
                            return;
                          }
                          setModalState(() => selected = next);
                        },
                      ),
                    if (!hasExifGps && hasDeviceGps)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(
                          'This photo did not include GPS data. We will use your current device location unless you cancel.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    if (!hasExifGps && !hasDeviceGps)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(
                          'No GPS could be determined (photo had no GPS and device GPS is unavailable).',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (chosenLatLng != null)
                      _KeyValueRow(
                        label: 'Will save',
                        value:
                            '${chosenLatLng.latitude.toStringAsFixed(6)}, ${chosenLatLng.longitude.toStringAsFixed(6)}',
                        valueColor: Colors.white,
                      ),
                    _KeyValueRow(
                      label: 'Timestamp',
                      value: resolvedTimestamp.toLocal().toString(),
                      valueColor: Colors.white,
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: chosenLatLng == null
                            ? null
                            : () {
                                Navigator.pop(
                                  context,
                                  _PostLooConfirmation(
                                    latLng: chosenLatLng,
                                    timestamp: resolvedTimestamp,
                                  ),
                                );
                              },
                        icon: const Icon(Icons.cloud_upload),
                        label: const Text('Post Loo'),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, null),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
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

  String _driveTimeFromKm(double km) {
    const averageKmh = 40.0;
    final minutes = (km / averageKmh * 60).round().clamp(1, 9999);
    if (minutes >= 60) {
      final hours = (minutes / 60).floor();
      final rem = minutes % 60;
      return rem == 0 ? '${hours}h' : '${hours}h ${rem}m';
    }
    return '${minutes}m';
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
                        )
                      : pages[_selectedIndex],
                ),
                if (_uploading)
                  _UploadingOverlay(
                    title: _busyTitle ?? 'Working…',
                    subtitle: _busySubtitle ?? 'Please wait.',
                  ),
              ],
            ),
          ),
          bottomNavigationBar: _BottomNav(
            selectedIndex: _selectedIndex,
            onTap: _onNavTap,
          ),
        );
      },
    );
  }

  Widget _buildMapWithNearestPanel({
    required Widget map,
    required _NearestToilet? nearest,
  }) {
    const navHeight = _BottomNav.height;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Stack(
      children: [
        Positioned.fill(child: map),
        Positioned(
          left: 12,
          right: 12,
          bottom: navHeight + bottomInset + 12,
          child: Center(child: _buildFindLooButton(nearest)),
        ),
      ],
    );
  }

  Widget _buildFindLooButton(_NearestToilet? nearest) {
    final hasNearest = nearest != null;
    final title = hasNearest
        ? 'Nearest Loo: ${nearest.distanceKm.toStringAsFixed(2)} km'
        : 'Nearest Loo: --';
    final subtitle = hasNearest
        ? 'Estimated drive time: ${_driveTimeFromKm(nearest.distanceKm)}'
        : 'Waiting for location/data';
    return SizedBox(
      width: math.min(MediaQuery.of(context).size.width * 0.85, 420),
      height: 76,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.amber,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 6,
        ),
        onPressed: hasNearest ? () => _openExternalMap(nearest.location) : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
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
      builder: (context) {
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        final canDelete = currentUid != null && currentUid == toilet.createdBy;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _ToiletImagePreview(toilet: toilet),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Date Posted: ${toilet.timestamp.toLocal()}',
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
                                  onPressed: () => Navigator.pop(context, true),
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
                FilledButton.icon(
                  onPressed: () => _openExternalMap(toilet.latLng),
                  icon: const Icon(Icons.map),
                  label: const Text('Open in Maps'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteToilet(ToiletPoint toilet) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid != toilet.createdBy) {
      _showMessage('You can only delete loos you posted.');
      return;
    }
    if (_uploading) {
      return;
    }
    setState(() {
      _uploading = true;
      _busyTitle = 'Deleting loo…';
      _busySubtitle = 'Removing photo and record.';
    });
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
        setState(() {
          _uploading = false;
          _busyTitle = null;
          _busySubtitle = null;
        });
      }
    }
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
  });

  static const LatLng _utrecht = LatLng(52.0907, 5.1214);

  final MapController mapController;
  final List<ToiletPoint> toilets;
  final void Function(ToiletPoint toilet) onMarkerTap;
  final LatLng? initialCenter;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        // Default to Utrecht while we fetch user GPS and recenter.
        initialCenter: initialCenter ?? _utrecht,
        initialZoom: initialCenter == null ? 13 : 16,
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
        MarkerLayer(
          markers: toilets
              .map(
                (toilet) => Marker(
                  point: toilet.latLng,
                  width: 46,
                  height: 46,
                  child: GestureDetector(
                    onTap: () => onMarkerTap(toilet),
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.amber, width: 2),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black54,
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.wc, color: Colors.amber, size: 26),
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
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

class _ToiletImagePreview extends StatelessWidget {
  const _ToiletImagePreview({required this.toilet});

  final ToiletPoint toilet;

  Future<String?> _resolveUrl() async {
    final url = toilet.imageUrl.trim();
    if (url.isEmpty) {
      return null;
    }
    if (url.startsWith('gs://')) {
      return FirebaseStorage.instance.refFromURL(url).getDownloadURL();
    }
    return url;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _resolveUrl(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ColoredBox(
            color: Colors.black26,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final url = snapshot.data;
        if (url == null || url.isEmpty) {
          return const ColoredBox(
            color: Colors.black26,
            child: Center(child: Icon(Icons.broken_image, color: Colors.white)),
          );
        }
        return Image.network(
          url,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              return child;
            }
            return const ColoredBox(
              color: Colors.black26,
              child: Center(child: CircularProgressIndicator()),
            );
          },
          errorBuilder: (context, error, stackTrace) => const ColoredBox(
            color: Colors.black26,
            child: Center(child: Icon(Icons.broken_image, color: Colors.white)),
          ),
        );
      },
    );
  }
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
          NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
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

enum _LocationChoice { exif, device }

class _PostLooConfirmation {
  const _PostLooConfirmation({required this.latLng, required this.timestamp});

  final LatLng? latLng;
  final DateTime timestamp;
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(color: valueColor, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
