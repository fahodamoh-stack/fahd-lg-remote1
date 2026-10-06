import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'lg_tv.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LgRemoteApp());
}

class LgRemoteApp extends StatelessWidget {
  const LgRemoteApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumina — LG Remote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0E17),
        fontFamily: 'Roboto',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE5484D),
          secondary: Color(0xFFF5B638),
          surface: Color(0xFF121624),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final LgTv tv = LgTv();
  late TabController _tabs;
  bool busy = false;
  bool connected = false;
  String status = 'Not connected — same Wi-Fi as the TV';
  List<Map<String, String>> devices = [];
  final ipCtrl = TextEditingController();
  final toastCtrl = TextEditingController();
  final urlCtrl = TextEditingController();
  final ytCtrl = TextEditingController();
  double volume = 20;
  bool muted = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    tv.states.listen((s) {
      if (!mounted) return;
      setState(() => status = s.message);
      if (s.error) _snack(s.message, err: true);
    });
  }

  @override
  void dispose() {
    tv.dispose();
    _tabs.dispose();
    ipCtrl.dispose();
    toastCtrl.dispose();
    urlCtrl.dispose();
    ytCtrl.dispose();
    super.dispose();
  }

  void _snack(String m, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m, maxLines: 3, overflow: TextOverflow.ellipsis),
      backgroundColor: err ? const Color(0xFF3A1416) : const Color(0xFF1A2136),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _run(Future<void> Function() fn, [String? ok]) async {
    if (!connected) {
      _snack('Connect to a TV first', err: true);
      return;
    }
    HapticFeedback.lightImpact();
    try {
      await fn();
      if (ok != null) _snack(ok);
    } catch (e) {
      _snack(_cleanErr(e), err: true);
    }
  }

  String _cleanErr(Object e) {
    var s = e.toString().replaceAll('Exception: ', '').replaceAll('TimeoutException: ', '');
    if (s.length > 140) s = '${s.substring(0, 140)}…';
    return s;
  }

  Future<void> scan() async {
    setState(() => busy = true);
    try {
      final list = await LgTv.discover(seconds: 4);
      setState(() => devices = list);
      if (list.isEmpty) {
        _snack('No TV found — enter IP manually (TV Settings → Network)',
            err: true);
      }
    } catch (e) {
      _snack(_cleanErr(e), err: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> connectTo(String ip) async {
    setState(() {
      busy = true;
      status = 'Pairing with $ip — accept prompt on TV…';
    });
    try {
      await tv.connect(ip.trim());
      setState(() {
        connected = true;
        status = 'Connected to $ip';
      });
      _tabs.animateTo(1);
      _snack('Connected — pairing saved');
    } catch (e) {
      setState(() => status = _cleanErr(e));
      _snack(_cleanErr(e), err: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _Backdrop(),
          SafeArea(
            child: Column(
              children: [
                _header(),
                _statusPill(),
                TabBar(
                  controller: _tabs,
                  indicatorColor: const Color(0xFFE5484D),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  tabs: const [
                    Tab(text: 'Connect'),
                    Tab(text: 'Remote'),
                    Tab(text: 'Cast'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _connectTab(),
                      _remoteTab(),
                      _castTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE5484D), Color(0xFF7C2D6B), Color(0xFF2B3A8F)],
              ),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFFE5484D).withOpacity(0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: const Icon(Icons.tv_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LUMINA',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2)),
                Text('LG webOS remote • premium',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          _dot(connected),
        ],
      ),
    );
  }

  Widget _dot(bool on) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: on ? const Color(0xFF123B2A) : const Color(0xFF1A2136),
        border: Border.all(
            color: on ? const Color(0xFF2FD57F) : Colors.white12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? const Color(0xFF2FD57F) : const Color(0xFFE5484D),
          ),
        ),
        const SizedBox(width: 6),
        Text(on ? 'LIVE' : 'OFFLINE',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _statusPill() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withOpacity(0.05),
          border: Border.all(color: Colors.white.withOpacity(0.09)),
        ),
        child: Row(children: [
          if (busy)
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            const Icon(Icons.info_outline, size: 16, color: Colors.white60),
          const SizedBox(width: 10),
          Expanded(
              child: Text(status,
                  style:
                      const TextStyle(fontSize: 12.5, color: Colors.white70))),
        ]),
      ),
    );
  }

  // ---------------- CONNECT ----------------
  Widget _connectTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      children: [
        _card(children: [
          const Text('1 — Same Wi-Fi',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text(
              'Phone and LG TV must be on the same Wi-Fi network. On TV: Settings → Network → Wi-Fi Connection.',
              style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: busy ? null : scan,
                icon: const Icon(Icons.radar, size: 18),
                label: Text(busy ? 'Scanning…' : 'Scan for TVs'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE5484D),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ]),
        ]),
        const SizedBox(height: 12),
        _card(children: [
          const Text('Found TVs',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (devices.isEmpty)
            const Text('Nothing yet — scan or enter IP below.',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          for (final d in devices)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: busy ? null : () => connectTo(d['ip']!),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white.withOpacity(0.04),
                    border:
                        Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.tv, color: Color(0xFFF5B638)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(d['name'] ?? 'LG TV',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          Text(d['ip'] ?? '',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                        ])),
                    const Icon(Icons.arrow_forward_ios,
                        size: 14, color: Colors.white38),
                  ]),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        _card(children: [
          const Text('Manual IP (works with any webOS TV)',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          TextField(
            controller: ipCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: '192.168.1.50',
              prefixIcon: const Icon(Icons.lan_outlined),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: busy
                  ? null
                  : () {
                      final v = ipCtrl.text.trim();
                      if (v.isEmpty) {
                        _snack('Enter TV IP first', err: true);
                        return;
                      }
                      connectTo(v);
                    },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                side: const BorderSide(color: Color(0xFFE5484D)),
                foregroundColor: Colors.white,
              ),
              child: const Text('Connect & Pair'),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
              'First time the TV shows “Allow connection?” — press Allow. The key is saved, next time auto-pairs.',
              style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5)),
          if (connected)
            TextButton.icon(
              onPressed: () {
                tv.disconnect();
                setState(() {
                  connected = false;
                  status = 'Disconnected';
                });
              },
              icon: const Icon(Icons.link_off, size: 16),
              label: const Text('Disconnect'),
            ),
        ]),
      ],
    );
  }

  // ---------------- REMOTE ----------------
  Widget _remoteTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      children: [
        _card(children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Direction pad',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              Icon(Icons.gamepad_outlined,
                  color: Colors.white.withOpacity(0.4)),
            ],
          ),
          const SizedBox(height: 14),
          _dpad(),
          const SizedBox(height: 12),
          Row(children: [
            _pillBtn(Icons.home_outlined, 'Home', () => _run(tv.home)),
            _pillBtn(Icons.arrow_back, 'Back', () => _run(tv.back)),
            _pillBtn(Icons.close, 'Exit', () => _run(tv.exitApp)),
          ]),
        ]),
        const SizedBox(height: 12),
        _card(children: [
          Row(children: [
            const Icon(Icons.volume_up_outlined, color: Color(0xFFF5B638)),
            const SizedBox(width: 8),
            const Text('Volume',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            Switch(
                value: muted,
                activeColor: const Color(0xFFE5484D),
                onChanged: (v) {
                  setState(() => muted = v);
                  _run(() => tv.setMuted(v));
                }),
          ]),
          Slider(
            value: volume,
            min: 0,
            max: 100,
            activeColor: const Color(0xFFE5484D),
            onChanged: (v) => setState(() => volume = v),
            onChangeEnd: (v) => _run(() => tv.setVolume(v.toInt())),
          ),
          Row(children: [
            _pillBtn(Icons.remove, 'Vol −', () => _run(tv.volumeDown)),
            _pillBtn(Icons.add, 'Vol +', () => _run(tv.volumeUp)),
            _pillBtn(Icons.tv_outlined, 'Live TV', () => _run(tv.liveTv)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            _pillBtn(Icons.keyboard_arrow_up, 'Ch +',
                () => _run(tv.channelUp)),
            _pillBtn(Icons.keyboard_arrow_down, 'Ch −',
                () => _run(tv.channelDown)),
            _pillBtn(Icons.power_settings_new, 'Off',
                () => _run(tv.powerOff, 'TV turning off…')),
          ]),
        ]),
        const SizedBox(height: 12),
        _card(children: [
          const Text('Apps', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: [
              _appTile('YouTube', Icons.play_circle_fill,
                  () => _run(tv.youtube)),
              _appTile('Netflix', Icons.movie_outlined,
                  () => _run(tv.netflix)),
              _appTile('Browser', Icons.language,
                  () => _run(() => tv.openUrl('https://www.google.com'))),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: toastCtrl,
            decoration: InputDecoration(
              hintText: 'Show message on TV…',
              prefixIcon: const Icon(Icons.message_outlined),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final t = toastCtrl.text.trim();
                if (t.isEmpty) return;
                _run(() => tv.toast(t), 'Sent to TV');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Show on TV',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      ],
    );
  }

  // ---------------- CAST ----------------
  Widget _castTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      children: [
        _card(children: [
          const Text('Cast YouTube',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Paste any YouTube link — opens instantly on the TV.',
              style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 10),
          TextField(
            controller: ytCtrl,
            decoration: InputDecoration(
              hintText: 'https://youtube.com/watch?v=…',
              prefixIcon: const Icon(Icons.ondemand_video),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _run(
                  () => tv.youtube(
                      ytCtrl.text.trim().isEmpty ? null : ytCtrl.text.trim()),
                  'Opening on TV…'),
              icon: const Icon(Icons.cast_connected),
              label: const Text('Play on TV'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE5484D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        _card(children: [
          const Text('Open link / media URL',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text(
              'Any direct mp4 / jpg / web page URL on your network. For phone photos: upload first (e.g. file transfer site) then paste link — iOS blocks direct local serving.',
              style: TextStyle(
                  color: Colors.white54, fontSize: 12.5, height: 1.5)),
          const SizedBox(height: 10),
          TextField(
            controller: urlCtrl,
            decoration: InputDecoration(
              hintText: 'https://…/video.mp4',
              prefixIcon: const Icon(Icons.link),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                final u = urlCtrl.text.trim();
                if (u.isEmpty) {
                  _snack('Paste a link first', err: true);
                  return;
                }
                _run(() => tv.openUrl(u), 'Opening on TV…');
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open on TV'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            _pillBtn(Icons.play_arrow, 'Play', () => _run(tv.play)),
            _pillBtn(Icons.pause, 'Pause', () => _run(tv.pause)),
            _pillBtn(Icons.stop, 'Stop', () => _run(tv.stop)),
          ]),
        ]),
      ],
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF121624).withOpacity(0.9),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 24,
              offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _pillBtn(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withOpacity(0.06),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(children: [
              Icon(icon, size: 19),
              const SizedBox(height: 4),
              Text(label,
                  style:
                      const TextStyle(fontSize: 11, color: Colors.white70)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _appTile(String name, IconData icon, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.09),
              Colors.white.withOpacity(0.03),
            ],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 22),
          const SizedBox(height: 6),
          Text(name, style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _dpad() {
    btn(IconData i, VoidCallback fn) => InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: fn,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.06),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Icon(i),
          ),
        );
    return Center(
      child: SizedBox(
        width: 210,
        height: 210,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
                top: 0, child: btn(Icons.keyboard_arrow_up, () => _run(() => tv.sendKey('up')))),
            Positioned(
                bottom: 0,
                child: btn(Icons.keyboard_arrow_down, () => _run(() => tv.sendKey('down')))),
            Positioned(
                left: 0,
                child: btn(Icons.keyboard_arrow_left, () => _run(() => tv.sendKey('left')))),
            Positioned(
                right: 0,
                child: btn(Icons.keyboard_arrow_right, () => _run(() => tv.sendKey('right')))),
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _run(() => tv.sendKey('ok')),
              child: Container(
                width: 78,
                height: 78,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFE5484D), Color(0xFF8E2B5E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                alignment: Alignment.center,
                child: const Text('OK',
                    style: TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 17)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();
  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0B0E17),
              Color(0xFF101527),
              Color(0xFF0B0E17),
            ],
          ),
        ),
      ),
      Positioned(
        top: -80,
        right: -60,
        child: Container(
          width: 280,
          height: 280,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              const Color(0xFFE5484D).withOpacity(0.28),
              Colors.transparent,
            ]),
          ),
        ),
      ),
      Positioned(
        top: 120,
        left: -80,
        child: Container(
          width: 260,
          height: 260,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              const Color(0xFF2B3A8F).withOpacity(0.35),
              Colors.transparent,
            ]),
          ),
        ),
      ),
    ]);
  }
}
