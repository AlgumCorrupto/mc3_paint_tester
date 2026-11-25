# MC3 Car Paint addon + demo project

* `addons/mc3_car_paint/` - the addon (see its README). Classes: `MC3CarPaint`, `MC3CarPaintPanel`.
  Car paint, chrome and glass materials, rebuilt from an Xbox capture.
* `demo/` - demo scene using only the public API: the sample car, a sphere, and three chrome test pieces
  (rim, ball, exhaust tube) in the chrome groups and three glass test pieces (smoked, headlight, brakelight).

Open the folder in Godot 4.3+ (4.2 should work), let it import the glTF, press F5.
Drag = orbit, wheel = zoom.

## Credits
Model: "Paint tester" by tifaiter, https://sketchfab.com/3d-models/paint-tester-72688c1de13348199dda4899b261b5b7,
licensed CC-BY-4.0 (see `demo/model/license.txt`). The model is only used by the demo, not by the addon.

The demo uses `demo/textures/garage_panorama.jpg` (supplied by the project owner) as the env map source and as the scene
background. Check that image's licence before redistributing the project.
