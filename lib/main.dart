import 'dart:io';
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
    setState(() => _uploading = true);
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
      );
      if (picked == null) {
        return;
      }
      final bytes = await picked.readAsBytes();
      final _ExtractedMetadata metadata = await _extractMetadata(bytes);
      final Position? fallbackPosition = metadata.latLng == null
          ? await _getCurrentPositionWithPermissions()
          : null;
      final LatLng? finalLatLng =
          metadata.latLng ??
          (fallbackPosition == null
              ? null
              : LatLng(fallbackPosition.latitude, fallbackPosition.longitude));
      if (finalLatLng == null) {
        _showMessage('Could not determine location. Enable GPS and try again.');
        return;
      }
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showMessage('You need to be logged in to post a loo.');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final storageRef = FirebaseStorage.instance.ref().child(
        'toilets/$now.jpg',
      );
      if (kIsWeb) {
        await storageRef.putData(bytes);
      } else {
        await storageRef.putFile(File(picked.path));
      }
      final imageUrl = await storageRef.getDownloadURL();

      await _toiletCollection.add({
        'imageUrl': imageUrl,
        'location': GeoPoint(finalLatLng.latitude, finalLatLng.longitude),
        'timestamp': Timestamp.fromDate(metadata.timestamp ?? DateTime.now()),
        'createdBy': user.uid,
      });
      _showMessage('Loo posted successfully.');
      await _refreshCurrentLocation();
    } catch (_) {
      _showMessage('Failed to post loo. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
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
          latLng = LatLng(normalizedLat, normalizedLon);
        }
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
    if (values.length < 3) {
      return null;
    }
    final d = _toDouble(values[0]);
    final m = _toDouble(values[1]);
    final s = _toDouble(values[2]);
    if (d == null || m == null || s == null) {
      return null;
    }
    return d + (m / 60) + (s / 3600);
  }

  double? _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is Ratio) {
      return value.toDouble();
    }
    final text = value.toString().trim();
    if (text.contains('/')) {
      final parts = text.split('/');
      if (parts.length == 2) {
        final n = double.tryParse(parts[0]);
        final d = double.tryParse(parts[1]);
        if (n != null && d != null && d != 0) {
          return n / d;
        }
      }
    }
    return double.tryParse(text);
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
            child: _selectedIndex == 1
                ? _buildMapWithNearestPanel(map: pages[1], nearest: nearest)
                : pages[_selectedIndex],
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
                    child: Image.network(
                      toilet.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: Colors.black26,
                        child: Center(
                          child: Icon(Icons.broken_image, color: Colors.white),
                        ),
                      ),
                    ),
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

  final MapController mapController;
  final List<ToiletPoint> toilets;
  final void Function(ToiletPoint toilet) onMarkerTap;
  final LatLng? initialCenter;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: initialCenter ?? const LatLng(51.5074, -0.1278),
        initialZoom: initialCenter == null ? 12 : 16,
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
                  width: 44,
                  height: 44,
                  child: GestureDetector(
                    onTap: () => onMarkerTap(toilet),
                    child: const Center(
                      child: Text('🚽', style: TextStyle(fontSize: 30)),
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
    required this.latLng,
    required this.imageUrl,
    required this.timestamp,
  });

  final LatLng latLng;
  final String imageUrl;
  final DateTime timestamp;

  factory ToiletPoint.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final geo = data['location'] as GeoPoint?;
    final ts = data['timestamp'] as Timestamp?;
    return ToiletPoint(
      latLng: LatLng(geo?.latitude ?? 0, geo?.longitude ?? 0),
      imageUrl: (data['imageUrl'] as String?) ?? '',
      timestamp: ts?.toDate() ?? DateTime.now(),
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
