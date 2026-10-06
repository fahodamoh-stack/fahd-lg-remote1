import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tiny UI sounds. All failures are silent — sound must never crash UI.
class SoundService {
  static final SoundService instance = SoundService._();
  SoundService._();

  final AudioPlayer _p = AudioPlayer();
  bool enabled = true;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool('fa_sound') ?? true;
    } catch (_) {}
  }

  Future<void> setEnabled(bool v) async {
    enabled = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('fa_sound', v);
    } catch (_) {}
  }

  Future<void> _play(String f) async {
    if (!enabled) return;
    try {
      await _p.play(AssetSource('sounds/$f'));
    } catch (_) {}
  }

  Future<void> tap() => _play('tap.wav');
  Future<void> toggle() => _play('toggle.wav');
  Future<void> success() => _play('success.wav');
  Future<void> error() => _play('error.wav');
}
