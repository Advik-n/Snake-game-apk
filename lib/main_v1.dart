// Flutter Snake Game
// Single-file example (main.dart). Assumptions made:
// - Play area: 50 x 50 logical cells (GRID_SIZE = 50).
// - Movement resolution: 1/4 cell (i.e. step = 0.25 logical units per tick).
// - On-screen joystick (bottom-left) controls movement direction.
// - Head one colour, body another colour with a simple pattern.
// - Score (current + best) persisted using shared_preferences.
// - Vibrant/neon theme: dark background, glowing snake and neon grid.

// To use this file:
// 1) Create a new Flutter project: `flutter create snake_game`
// 2) Replace lib/main.dart with this file.
// 3) Add dependencies in pubspec.yaml:
//    shared_preferences: ^2.1.1
// 4) Run `flutter pub get`
// 5) Run `flutter run` to test or `flutter build apk --release` to build APK.

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(MyApp(prefs: prefs));
}

class MyApp extends StatelessWidget {
  final SharedPreferences prefs;
  const MyApp({required this.prefs, Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Neon Snake',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: GamePage(prefs: prefs),
    );
  }
}

class GamePage extends StatefulWidget {
  final SharedPreferences prefs;
  const GamePage({required this.prefs, Key? key}) : super(key: key);
  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with SingleTickerProviderStateMixin {
  static const int GRID_SIZE = 50; // 50 x 50 logical cells
  static const double TURN_RESOLUTION = 0.25; // quarter cell turning resolution
  static const double TICKS_PER_SEC = 30; // game loop tick rate

  late double stepPerTick; // in logical units (cells)
  Timer? gameTimer;
  Size screenSize = Size.zero;

  // Snake represented as list of positions in logical units (x,y) where 0..GRID_SIZE
  List<Offset> snake = [];
  Offset direction = Offset(1, 0); // normalized in logical units per tick (unit vector)
  double speedUnitsPerSec = 6.0; // cells per second (tweakable)

  Offset food = Offset.zero;
  Random rnd = Random();

  int score = 0;
  int best = 0;

  bool running = false;
  bool gameOver = false;

  // joystick
  Offset joystickCenter = Offset.zero;
  double joystickSize = 100;
  Offset joystickPointer = Offset.zero;
  bool joystickActive = false;

  @override
  void initState() {
    super.initState();
    best = widget.prefs.getInt('best_score') ?? 0;
    resetGame();
  }

  @override
  void dispose() {
    gameTimer?.cancel();
    super.dispose();
  }

  void resetGame() {
    snake.clear();
    // start snake at centre with length 4, spaced by 1 unit
    final center = Offset(GRID_SIZE / 2, GRID_SIZE / 2);
    snake.addAll([
      center,
      center - Offset(1, 0),
      center - Offset(2, 0),
      center - Offset(3, 0),
    ]);
    direction = Offset(1, 0);
    score = 0;
    gameOver = false;
    running = false;
    placeFood();
    // step per tick depends on speed and tick rate
    stepPerTick = speedUnitsPerSec / TICKS_PER_SEC;
    startLoop();
    setState(() {});
  }

  void startLoop() {
    gameTimer?.cancel();
    gameTimer = Timer.periodic(Duration(milliseconds: (1000 / TICKS_PER_SEC).round()), (_) {
      tick();
    });
  }

  void tick() {
    if (gameOver) return;
    // if joystick inactive, don't move unless running (allows pause)
    if (!running) return;

    // move head by stepPerTick along direction
    final newHead = _wrapIfNeeded(snake.first + direction * stepPerTick);

    // insert
    snake.insert(0, newHead);

    // did we hit food? distance < half cell
    if ((newHead - food).distance < 0.5) {
      score += 1;
      placeFood();
    } else {
      // remove tail
      snake.removeLast();
    }

    // self collision: if head is within 0.3 units of any body segment (after index 2)
    for (int i = 3; i < snake.length; i++) {
      if ((snake[i] - newHead).distance < 0.3) {
        onGameOver();
        break;
      }
    }

    setState(() {});
  }

  Offset _wrapIfNeeded(Offset p) {
    double x = p.dx;
    double y = p.dy;
    // wrap around edges
    if (x < 0) x += GRID_SIZE;
    if (x >= GRID_SIZE) x -= GRID_SIZE;
    if (y < 0) y += GRID_SIZE;
    if (y >= GRID_SIZE) y -= GRID_SIZE;
    return Offset(x, y);
  }

  void placeFood() {
    // pick random empty cell (avoid snake body)
    for (int tries = 0; tries < 1000; tries++) {
      final fx = rnd.nextInt(GRID_SIZE) + rnd.nextDouble();
      final fy = rnd.nextInt(GRID_SIZE) + rnd.nextDouble();
      final pos = Offset(fx, fy);
      bool coll = false;
      for (final s in snake) {
        if ((s - pos).distance < 0.8) {
          coll = true;
          break;
        }
      }
      if (!coll) {
        food = pos;
        return;
      }
    }
    // fallback
    food = Offset(rnd.nextDouble() * GRID_SIZE, rnd.nextDouble() * GRID_SIZE);
  }

  void onGameOver() {
    gameOver = true;
    running = false;
    if (score > best) {
      best = score;
      widget.prefs.setInt('best_score', best);
    }
    setState(() {});
  }

  void setDirectionFromJoystick(Offset v) {
    if (v.distance < 0.01) return; // ignore tiny
    // convert to logical direction and snap to TURN_RESOLUTION multiples
    final ang = atan2(v.dy, v.dx);
    final dx = cos(ang);
    final dy = sin(ang);
    // normalize and snap to TURN_RESOLUTION grid: we want direction as multiples of 0.25 of cell
    // We'll compute a direction vector with continuous values but when moving we effectively step by stepPerTick
    direction = Offset(dx, dy) / sqrt(dx * dx + dy * dy);
  }

  // helper: convert logical units to screen pixels
  double cellSizeFromScreen(Size s) {
    // keep square grid that fits inside screen with padding for joystick UI
    final pad = 16.0;
    final availW = s.width - pad * 2;
    final availH = s.height - 140 - pad; // reserve bottom for joystick/UI
    final cell = min(availW / GRID_SIZE, availH / GRID_SIZE);
    return cell;
  }

  @override
  Widget build(BuildContext context) {
    screenSize = MediaQuery.of(context).size;
    joystickSize = min(140.0, screenSize.width * 0.28);
    joystickCenter = Offset(joystickSize / 2 + 12, screenSize.height - joystickSize / 2 - 24);
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Game canvas
            Positioned.fill(
              child: LayoutBuilder(builder: (context, constraints) {
                final cellSize = cellSizeFromScreen(constraints.biggest);
                final boardPixW = cellSize * GRID_SIZE;
                final boardPixH = cellSize * GRID_SIZE;
                final left = (constraints.maxWidth - boardPixW) / 2;
                final top = 16.0;
                return Stack(children: [
                  Positioned(left: left, top: top, width: boardPixW, height: boardPixH, child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      boxShadow: [BoxShadow(color: Colors.cyan.withOpacity(0.08), blurRadius: 12, spreadRadius: 1)],
                    ),
                    child: CustomPaint(
                      painter: _SnakePainter(
                        snake: snake,
                        food: food,
                        gridSize: GRID_SIZE,
                        cellSize: cellSize,
                      ),
                    ),
                  )),
                ]);
              }),
            ),

            // Top HUD (score)
            Positioned(top: 12, left: 16, right: 16, child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Score: $score', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                  Text('Best: $best', style: TextStyle(fontSize: 14, color: Colors.greenAccent)),
                ]),
                Row(children: [
                  ElevatedButton(onPressed: () {
                    setState(() { running = !running; });
                  }, child: Text(running ? 'Pause' : 'Play')),
                  SizedBox(width: 8),
                  ElevatedButton(onPressed: resetGame, child: Text('Restart'))
                ])
              ],
            )),

            // Joystick (bottom-left)
            Positioned(left: 8, bottom: 8, child: GestureDetector(
              onPanStart: (d) {
                joystickActive = true;
                joystickPointer = d.localPosition;
                setDirectionFromJoystick((d.localPosition - Offset(joystickSize/2, joystickSize/2))/ (joystickSize/2));
                running = true; // start moving when joystick touched
                setState(() {});
              },
              onPanUpdate: (d) {
                joystickPointer = d.localPosition;
                final rel = (d.localPosition - Offset(joystickSize/2, joystickSize/2)) / (joystickSize/2);
                final capped = Offset(rel.dx.clamp(-1.0, 1.0), rel.dy.clamp(-1.0, 1.0));
                setDirectionFromJoystick(capped);
              },
              onPanEnd: (d) {
                joystickActive = false;
                // stop movement when released? keep moving in last dir — user asked joystick to control movement; we'll pause when released
                running = false;
                setState(() {});
              },
              child: CustomPaint(
                size: Size(joystickSize, joystickSize),
                painter: _JoystickPainter(active: joystickActive, pointer: joystickPointer),
              ),
            )),

            // Bottom-right: small controls/info
            Positioned(right: 12, bottom: 24, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Neon theme', style: TextStyle(color: Colors.deepPurpleAccent, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              ElevatedButton(onPressed: () { setState(() { speedUnitsPerSec = (speedUnitsPerSec % 12) + 2; stepPerTick = speedUnitsPerSec / TICKS_PER_SEC; }); }, child: Text('Speed: ${speedUnitsPerSec.toStringAsFixed(0)}')),
            ])),

            // Game Over overlay
            if (gameOver)
              Positioned.fill(child: Container(color: Colors.black54, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Game Over', style: TextStyle(fontSize: 42, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                SizedBox(height: 12),
                Text('Score: $score', style: TextStyle(fontSize: 22, color: Colors.white)),
                SizedBox(height: 12),
                ElevatedButton(onPressed: resetGame, child: Text('Play Again'))
              ])))),
          ],
        ),
      ),
    );
  }
}

class _SnakePainter extends CustomPainter {
  final List<Offset> snake;
  final Offset food;
  final int gridSize;
  final double cellSize;
  _SnakePainter({required this.snake, required this.food, required this.gridSize, required this.cellSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // draw neon grid
    paint.color = Colors.white.withOpacity(0.04);
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1;
    for (int i = 0; i <= gridSize; i++) {
      final dx = i * cellSize;
      canvas.drawLine(Offset(dx, 0), Offset(dx, cellSize * gridSize), paint);
      final dy = i * cellSize;
      canvas.drawLine(Offset(0, dy), Offset(cellSize * gridSize, dy), paint);
    }

    // draw food
    final foodPix = Offset(food.dx * cellSize, food.dy * cellSize);
    final foodR = cellSize * 0.45;
    final foodPaint = Paint()..shader = RadialGradient(colors: [Colors.pinkAccent, Colors.orangeAccent]).createShader(Rect.fromCircle(center: foodPix, radius: foodR));
    canvas.drawCircle(foodPix, foodR, foodPaint);

    // draw snake body with pattern
    if (snake.isEmpty) return;

    for (int i = snake.length - 1; i >= 0; i--) {
      final p = snake[i];
      final center = Offset(p.dx * cellSize, p.dy * cellSize);
      final r = cellSize * 0.45;
      if (i == 0) {
        // head - bright cyan glow
        final headPaint = Paint()..shader = RadialGradient(colors: [Colors.cyanAccent, Colors.blueAccent]).createShader(Rect.fromCircle(center: center, radius: r));
        canvas.drawCircle(center, r, headPaint);
        // glow
        final glow = Paint()..color = Colors.cyanAccent.withOpacity(0.18);
        canvas.drawCircle(center, r * 1.8, glow);
      } else {
        // body - alternating pattern
        final c1 = Colors.deepPurpleAccent;
        final c2 = Colors.purpleAccent;
        final use = (i % 2 == 0) ? c1 : c2;
        final bodyPaint = Paint()..shader = RadialGradient(colors: [use.withOpacity(0.95), use.withOpacity(0.6)]).createShader(Rect.fromCircle(center: center, radius: r));
        canvas.drawCircle(center, r, bodyPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _JoystickPainter extends CustomPainter {
  final bool active;
  final Offset pointer;
  _JoystickPainter({required this.active, required this.pointer});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // base circle
    final base = Paint()..color = Colors.white.withOpacity(0.04);
    canvas.drawCircle(center, r, base);

    // ring
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..shader = SweepGradient(colors: [Colors.cyanAccent, Colors.purpleAccent]).createShader(rect);
    canvas.drawCircle(center, r - 6, ring);

    // pointer
    final p = pointer == Offset.zero ? center : pointer;
    final cap = Paint()..color = active ? Colors.cyanAccent : Colors.white24;
    canvas.drawCircle(p, size.width * 0.14, cap);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// NOTES and TWEAKS:
// - Movement uses continuous logical coordinates; turning is smooth thanks to joystick and we step by stepPerTick.
// - If you want discrete quarter-cell turning instead of free-angle, snap direction to the nearest 45/90-degree direction or quantize the head position to multiples of 0.25.
// - To make turns snap to quarter-cell increments, modify setDirectionFromJoystick to compute target angle and then snap head coordinate to nearest 0.25 multiple before starting to move in that direction.
// - For better visuals use a shader blur for glow (via BackdropFilter or third-party packages), add particle effects on eating, and attach sound effects using `audioplayers` package.

// BUILD / APK
// flutter build apk --release
// flutter install --apk=build/app/outputs/flutter-apk/app-release.apk

// ASSETS & THEMING SUGGESTIONS (neon/vibrant):
// - Background: almost-black gradient (#050014 -> #0b0229)
// - Grid lines: faint neon (rgba(255,255,255,0.06))
// - Head: cyan / aqua glow (neon cyan)
// - Body: alternating purple/pink gradients
// - Food: hot-pink/orange radial glow
// - Fonts: use a techno / geometric font (e.g., 'Orbitron')
// - Particle: small glow burst when eating

// PERFORMANCE:
// - This single-file example uses Timer.periodic and CustomPainter. For complex effects consider `Flame` game engine for best performance.
// - Reduce TICKS_PER_SEC or skip paint calls when offscreen to save CPU.

// Enjoy — tweak speeds, grid, and visuals. Happy coding!
