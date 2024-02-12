import 'dart:async';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

class FractalGenerator {
  int lastTime = 0;
  int canvasWidth = 1080;
  int canvasHeight = 1920;
  double resolutionScale = 0.075;
  int maxIterations = 300;
  double zoom = 300.0;
  double offsetX = 0;
  double offsetY = 0;
  bool paused = true;
  img.Image image = img.Image(100, 100);
  late StreamController<Uint8List> _imageStreamController;
  int skipGen = 3;
  int R = 5;
  int G = 5;
  int B = 5;



  //These parameters are for synchronisation purposes
  //Otherwise I will need to use prop drilling

  bool showTelemetry = true;
  bool useSysColor = true;
  String currentFractal = "Mandelbrot";

  FractalGenerator() {
    _imageStreamController = StreamController<Uint8List>();
  }

  Stream<Uint8List> get imageStream => _imageStreamController.stream;
  Future<void> generateMandelbrotFrame() async{
    var temptime = DateTime.now().millisecondsSinceEpoch;
    int picWidth = (canvasWidth * resolutionScale).toInt();
    int picHeight = (canvasHeight * resolutionScale).toInt();
    double halfResW = picWidth / 2;
    double halfResH = picHeight / 2;
    double zoomRes = zoom * resolutionScale;
    image = img.Image(picWidth, picHeight);
    for (int y = 0; y < picHeight; y++) {
      for (int x = 0; x < picWidth; x++) {
        double zx = (x - halfResW) / zoomRes + offsetX;
        double zy = (y - halfResH) / zoomRes + offsetY;

        double cX = zx;
        double cY = zy;

        int iteration = 0;
        while (iteration < maxIterations) {
          double zx2 = zx * zx;
          double zy2 = zy * zy;
          if (zx2 + zy2 > 4) {
            break;
          }

          double tmp = zx2 - zy2 + cX;
          zy = 2 * zx * zy + cY;
          zx = tmp;

          iteration++;
        }
        image.setPixel(x, y, img.getColor((iteration * R) % 255, (iteration * G) % 255, (iteration * B) % 255));
      }
    }
    lastTime = DateTime.now().millisecondsSinceEpoch - temptime;
    print("Frametime: $lastTime");
    _imageStreamController.add(Uint8List.fromList(img.encodeBmp(image)));
  }

  Future<void> generateSierpinskiFrame() async {
    var temptime = DateTime.now().millisecondsSinceEpoch;
    int picWidth = (canvasWidth * resolutionScale).toInt();
    int picHeight = (canvasHeight * resolutionScale).toInt();
    image = img.Image(picWidth, picHeight);

    for (int y = 0; y < picHeight; y++) {
      for (int x = 0; x < picWidth; x++) {
        double nx = (2 * (x / picWidth)) - 1;
        double ny = (2 * (y / picHeight)) - 1;

        if (isInsideSierpinskiTriangle(nx, ny)) {
          image.setPixel(x, y, img.getColor(((25.5 * R) % 255).toInt(), ((25.5 * G) % 255).toInt(), ((25.5 * B) % 255).toInt()));
        }
      }
    }
    lastTime = DateTime.now().millisecondsSinceEpoch - temptime;
    print("Frametime: $lastTime");
    _imageStreamController.add(Uint8List.fromList(img.encodeBmp(image)));
  }

  bool isInsideSierpinskiTriangle(double x, double y) {
    while (true) {
      if (x < 0 || x > 1 || y < 0 || y > 1) {
        return false;
      }
      if ((x + y) > 1) {
        return true;
      }
      x *= 2;
      y *= 2;
    }
  }


  Future<void> startReceivingFrames() async {
    for (;;) {
      if (paused) {
        if (resolutionScale == 0.075) {
          resolutionScale += 0.925;
          skipGen = 1;
        } else {
          if(skipGen>0){
            skipGen -=1;
          }
        }
      }else{
        skipGen = 1;
      }
      if (skipGen > 0) {
        switch(currentFractal){
          case "Mandelbrot":
            generateMandelbrotFrame();
            break;
          case "Sierpinski":
            generateSierpinskiFrame();
            break;
        }
      }
      await Future.delayed(const Duration(milliseconds: 1));
    }
  }

  void dispose() {
    _imageStreamController.close();
  }
}
