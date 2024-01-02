import 'dart:async';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

class FractalGenerator {
  int lastTime = 0;
  int canvasWidth = 100;
  int canvasHeight = 100;
  double resolutionScale = 0.075;
  int maxIterations = 200;
  double zoom = 300.0;
  double offsetX = 0;
  double offsetY = 0;
  bool paused = true;
  img.Image image = img.Image(100, 100);
  late StreamController<Uint8List> _imageStreamController;
  int skipGen = 5;
  int R = 0;
  int G = 5;
  int B = 5;

  FractalGenerator() {
    _imageStreamController = StreamController<Uint8List>();
  }

  Stream<Uint8List> get imageStream => _imageStreamController.stream;
  Future<void> generateFrame() async{
    var temptime = DateTime.now().millisecondsSinceEpoch;
    image = img.Image(canvasWidth, canvasHeight);
    for (int y = 0; y < canvasHeight; y++) {
      for (int x = 0; x < canvasWidth; x++) {
        double zx = (x - canvasWidth / 2) / (zoom * resolutionScale) + offsetX;
        double zy = (y - canvasHeight / 2) / (zoom * resolutionScale) + offsetY;

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
  }
  Future<void> startReceivingFrames() async {
    for (;;) {
      if (paused) {
        if (resolutionScale == 0.075) {
          resolutionScale += 0.925;
          skipGen = 3;
        } else {
          if(skipGen>0){
            skipGen -=1;
          }
        }
      }else{
        skipGen = 3;
      }
      if (skipGen > 0) {
        generateFrame();
      }
      _imageStreamController.add(Uint8List.fromList(img.encodeBmp(image)));
      await Future.delayed(const Duration(milliseconds: 1));
    }
  }

  void dispose() {
    _imageStreamController.close();
  }
}
