# SMILEY_CAM

## Description

SMILEY_CAM is a Flutter-based application that uses your device's camera to detect faces and automatically takes a picture when it detects a smile. It also includes a fun snow filter that can be enabled to add a wintery effect to your photos.

---
## Project Structure

The main application logic is contained within the following files:

* `lib/main.dart`: The main entry point of the application.
* `lib/home_screen.dart`: The main screen of the application, containing the camera preview, face detection logic, and UI elements.
* `lib/src/face_detector_painter.dart`: A custom painter for drawing face bounding boxes and landmarks on the camera preview.

---
## Features

* **Smile Detection**: Automatically captures a photo when a smile is detected.
* **Face Tracking**: Tracks multiple faces in real-time.
* **Snow Filter**: Apply a fun snow effect to your camera view and captured photos.
* **Camera Switching**: Easily switch between front and back cameras.
* **Manual Capture**: Manually capture photos with a button press.
* **Gallery Saver**: Saves captured photos to your device's gallery.

---
## Dependencies

* [flutter](https://flutter.dev/): The UI toolkit for building beautiful, natively compiled applications for mobile, web, and desktop from a single codebase.
* [camera](https://pub.dev/packages/camera): A Flutter plugin for controlling the device's camera.
* [google_ml_kit](https://pub.dev/packages/google_ml_kit): A Flutter plugin for using Google's ML Kit APIs.
* [permission_handler](https://pub.dev/packages/permission_handler): A Flutter plugin for requesting and checking permissions.
* [image_gallery_saver_plus](https://pub.dev/packages/image_gallery_saver_plus): A Flutter plugin for saving images and videos to the gallery.
* [path_provider](https://pub.dev/packages/path_provider): A Flutter plugin for finding commonly used locations on the filesystem.

---
## Getting Started

To get a local copy up and running follow these simple example steps.

---
### Prerequisites

* Flutter SDK: [https://flutter.dev/docs/get-started/install](https://flutter.dev/docs/get-started/install)
* Dart SDK: [https://dart.dev/get-dart](https://dart.dev/get-dart)

---
### Installation

1.  Clone the repo
    ```sh
    git clone [https://github.com/bntngbntng/SMILEY_CAM.git](https://github.com/bntngbntng/SMILEY_CAM.git)
    ```
2.  Install packages
    ```sh
    flutter pub get
    ```
3.  Run the app
    ```sh
    flutter run
    ```

---
## Usage

1.  Launch the application on your device.
2.  Grant the necessary camera and storage permissions.
3.  Point the camera at a face. The app will automatically detect faces and draw a bounding box around them.
4.  Smile! The app will detect your smile and automatically take a picture.
5.  You can also manually capture a photo by tapping the camera button at the bottom of the screen.
6.  Toggle the "Smile to Snap" feature by tapping the mood icon in the app bar.
7.  Toggle the snow filter by tapping the snowflake icon in the app bar.
8.  Switch between the front and back cameras using the camera switch icon.

---
## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

If you have a suggestion that would make this better, please fork the repo and create a pull request. You can also simply open an issue with the tag "enhancement".

1.  Fork the Project.
2.  Create your Feature Branch.
3.  Commit your Changes.
4.  Push to the Branch.
5.  Open a Pull Request.

---
## Note
1. **This repository is probably not going to be maintained.**
