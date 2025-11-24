# PCB Defect Classifier & Streamlit App

This project is an end-to-end pipeline for detecting defects on printed circuit boards (PCBs) using a convolutional neural network and an interactive Streamlit web app.

Hosted app : https://defectdestroyer.streamlit.app  

The backend model is trained on cropped defect patches from the Kaggle PCB Defects dataset and can classify six defect types:

- `missing_hole`
- `mouse_bite`
- `open_circuit`
- `short`
- `spur`
- `spurious_copper`

The Streamlit app lets a user:

1. Upload a microscope image of a PCB trace.
2. Interactively draw a square crop over a region of interest.
3. Submit the crop to the trained model.
4. See the most likely defect type (or “no defect detected” if confidence is low).


## 1. Code Structure

Final project files (in the “Final Submit Project” folder):

- `board_scanner.py`  
  Main Streamlit app. Handles:
  - File upload
  - Interactive square crop (via drawable canvas)
  - Preprocessing the crop to 224×224
  - Running inference with the trained model
  - Displaying the predicted defect type, confidence, and anomaly flag

- `dl_classifier.py`  
  Model training and evaluation script. Handles:
  - Building train/val/test datasets from `data/pcb_patches`
  - Defining the CNN architecture with data augmentation and BatchNorm
  - Class-weight computation for balanced training
  - Training loop with early stopping and ReduceLROnPlateau
  - Validation/test evaluation and confusion matrices
  - Saving:
    - `pcb_defect_classifier.keras`
    - `pcb_class_names.pkl`
    - `pcb_class_centroids.npy`
  - Convenience helpers for single-image prediction and anomaly scoring

- `prepare_dataset.py`  
  One-time dataset preparation script. Handles:
  - Downloading and unzipping the PCB Defects Kaggle dataset from https://www.kaggle.com/datasets/akhatova/pcb-defects/data into `data/raw_kaggle` (using the Kaggle CLI and your local `~/kaggle.json` credentials).
  - Parsing XML annotations to crop defect-centered patches from full board images.
  - Building the `data/pcb_patches/train|val|test/...` directory tree expected by `dl_classifier.py`.
  - Reusing an already-prepared `data/pcb_patches` tree if present (so users can run the project offline with a pre-packaged dataset).

- `pcb_defect_classifier.keras`  
  Trained Keras model loaded by `board_scanner.py` and the prediction helpers in `dl_classifier.py`.

- `pcb_class_names.pkl`  
  List of class names in the correct order. Used to map model outputs (indices) to labels.

- `pcb_class_centroids.npy`  
  Numpy array / dict of feature centroids for each class, used to compute anomaly scores.

- `requirements.txt`  
  Python dependencies for the Streamlit app and, mostly, for training.

- `README.txt`  
  This file.


## 2. Dependencies & Environments

All runtime dependencies for the Streamlit app are declared in `requirements.txt`:

```
streamlit>=1.30
tensorflow>=2.15,<3.0
numpy>=1.24,<3.0
Pillow>=10.0
joblib>=1.3
scikit-learn>=1.3
kaggle>=1.5
matplotlib>=3.8
pandas>=2.0
```

Additional packages used during training (already available in Colab and many Python distros, but listed here for completeness):

- `scikit-learn` (for `classification_report`, `confusion_matrix`, and `compute_class_weight`)

### Suggested local environment (example, Apple Silicon)

```bash
conda create -n pcbapp python=3.10
conda activate pcbapp
pip install -r requirements.txt
pip install scikit-learn
```

> On Apple Silicon, training from scratch may also use `tensorflow-macos` and `tensorflow-metal`. These are not required on Streamlit Cloud, where a standard TensorFlow build is used.


## 3. Datasets and Models

### 3.1 Public Kaggle dataset (training data)

The Streamlit app itself does not download the raw dataset automatically because Kaggle programmatic downloads require per-user API credentials and a terms-of-use agreement. These credentials cannot be safely embedded in a public repository or auto-run in all environments.

However, for offline training in this project, the script `prepare_dataset.py` can automatically:
- Download and unzip the Kaggle dataset into `data/raw_kaggle` using the Kaggle CLI (assuming you have `kaggle` installed and `/kaggle.json` configured), and
- Build cropped defect patches from the XML annotations into the `data/pcb_patches/train|val|test/...` structure.

Instead, to reproduce training from scratch, follow below:

In local environment of on Google Colab (automatic, offline)

1. Log into Kaggle and accept the terms for the PCB defects dataset.
2. Install the Kaggle CLI and place your API token at `/kaggle.json` (standard Kaggle setup).
3. From the project root, run:

   ```bash
   python prepare_dataset.py
   ```

   This will:
   - Download and unzip the PCB Defects dataset into `data/raw_kaggle`, and
   - Build the cropped defect patches into `data/pcb_patches/train|val|test/...`.

4. Run `dl_classifier.py` (see Section 5) to train and save the model and class centroids.

5. Lastly, run 'board_scanner.py' to launch the entire app

### 3.2 Real-world microscope images

Additional evaluation was performed on proprietary microscope images of evaluation modules (EVMs) from an industrial setting.  
These images cannot be included in the public repository due to company confidentiality. They are used only for qualitative testing and are not required to run the app.

### 3.3 Pre-trained model artifacts

For running the app without retraining:

- `pcb_defect_classifier.keras`
- `pcb_class_names.pkl`
- `pcb_class_centroids.npy`

These files are generated by `dl_classifier.py` after training. For local use:

- Either train from scratch (Section 5) to produce these files, or
- Download the provided artifacts from the course submission / release bundle and place them in the project root next to `board_scanner.py`.


## 4. How the App Works (High-Level)

1. **Model loading**
   - On startup, `board_scanner.py` loads:
     - `pcb_defect_classifier.keras`
     - `pcb_class_names.pkl`
     - `pcb_class_centroids.npy` (for anomaly checks)
   - The model expects 224×224 RGB images normalized to [0, 1].

2. **User workflow**
   - User opens the Streamlit app (hosted or local).
   - Uploads a PCB image (typically a microscope photo).
   - A drawable canvas is displayed with:
     - The uploaded image as the background.
     - A movable, resizable square crop box.
     - Controls to zoom in/out the displayed image.
   - The user positions the square over the trace region of interest and clicks Submit.
   - The app:
     - Extracts the selected region.
     - Resizes it to 224×224.
     - Normalizes the pixels.
     - Runs the patch through the CNN.

3. **Prediction and anomaly check**
   - The app computes class probabilities from the model’s softmax output.
   - It displays:
     - The predicted defect label.
     - The associated probability (e.g., “spur – 97.3%”).
   - If all probabilities are below a threshold, or the feature embedding lies far from all class centroids, the app shows:
     - “No defect detected with high confidence” or an “anomalous / unknown pattern” flag.


## 5. Running the Project

### 5.1 Hosted Streamlit app (no setup)

Simply visit:

- https://defectdestroyer.streamlit.app

Upload a PCB image, draw a square crop over a suspected defect, and submit to see the predicted label.


### 5.2 Run the Streamlit app locally

1. Ensure the following files are present in the project folder:

   - `board_scanner.py`
   - `requirements.txt`
   - `pcb_defect_classifier.keras`
   - `pcb_class_names.pkl`
   - `pcb_class_centroids.npy`
   - `README.txt`

2. Create and activate an environment, then install dependencies:

   ```bash
   conda create -n pcbapp python=3.10
   conda activate pcbapp
   pip install -r requirements.txt
   pip install scikit-learn
   ```

3. Launch the app:

   ```bash
    python -m streamlit run board_scanner.py
   ```

4. Open the provided local URL in a browser, upload an image, crop, and inspect predictions.


### 5.3 Re-train the model from scratch

1. Prepare the dataset (one time):
   - If you have Kaggle credentials configured, from the project root run:

     ```bash
     python prepare_dataset.py
     ```

     This will download the PCB Defects dataset (if needed) and build the `data/pcb_patches/train|val|test/...` directory tree.

   - Alternatively, manually create `data/pcb_patches/...` as described in Section 3.1.

2. Ensure `scikit-learn` is installed.
3. Run:

   ```bash
   python dl_classifier.py
   ```


## 6. Code Provenance and External Sources

Below is a breakdown for the final project files.

### 6.1 `dl_classifier.py`

- **Authorship:**  
  Written specifically for this project. The file integrates ideas discussed in ECE 570, but there is no direct copy-paste from public GitHub repositories.

- **Adapted patterns (not verbatim copies):**
  - **GPU configuration and memory growth:**  
    The pattern of calling `tf.config.experimental.list_physical_devices("GPU")`, enabling memory growth, and disabling XLA JIT follows typical code shown in official TensorFlow documentation and tutorials, but has been customized for this script (print messages, error handling).
  - Dataset creation with `image_dataset_from_directory`:
    The use of `tf.keras.utils.image_dataset_from_directory` for train/val/test splits, followed by `.cache().prefetch()`, is inspired by TensorFlow “image classification” examples. Paths, class checks, and debug prints are specific to this project.
  - Callbacks (`EarlyStopping`, `ReduceLROnPlateau`):
    The combination of early stopping on validation loss and `ReduceLROnPlateau` is a common Keras pattern. The specific hyperparameters (patience values, min LR, etc.) are chosen and tuned for this PCB defect task.

- Original / project-specific logic:
  - The CNN architecture in `build_model` (stack of Conv2D + BatchNorm + MaxPooling blocks with a `feature_dense` layer and dropout) was designed and tuned for the PCB patches.
  - The `build_datasets` function’s fallback behavior (using `BOARD_DATA_ROOT` if `DATA_ROOT` is missing) is project-specific.
  - The `compute_class_weights_from_ds` helper and its integration into the training loop are tailored to this dataset.
  - The evaluation logic (validation/test loops, printed confusion matrices via `print_confusion_matrix`, and `summarize_confusions`) is custom for this project.
  - The feature-extractor and centroid computation (`build_feature_extractor`, `compute_class_centroids`) and the anomaly-aware prediction helper (`predict_single_image_with_anomaly`) are project-specific additions for handling “no defect / unknown pattern” cases.

### 6.2 `board_scanner.py`

- **Authorship:**  
  Written for this project to serve as the GUI front end.

- Adapted elements:
  - The general pattern of using Streamlit for file upload (`st.file_uploader`) and laying out controls in columns follows the official Streamlit documentation.
  - The interactive cropping is based on the “drawable canvas” paradigm and uses a pattern similar to community examples of `streamlit-drawable-canvas`. The actual integration (square-only crop, normalization to model input, anomaly display) is custom.

- **Original / project-specific logic:**
  - The logic for converting canvas coordinates into a square crop on the original image.
  - The wiring between the crop, the trained model, the class names, and the anomaly score.
  - The UX flow tailored specifically to PCB traces (instructions, messaging, “no defect detected” handling).

## 7. Usage Tips & Limitations

- The model is trained on defect-centered patches from the Kaggle dataset. For best results, the crop in the app should:
  - Put the suspected defect near the center.
  - Include enough surrounding copper/board context without zooming out too far.

- The model only recognizes the six defect types listed above.
  - Other kinds of damage or unusual board layouts may be misclassified or flagged as “no defect / anomalous.”

- The current app processes one crop at a time.
  - It does not scan entire boards automatically or output defect counts.

Despite these limitations, the system provides a practical prototype for reducing tedious microscope inspection work: a lightweight CNN plus an intuitive GUI that allows an engineer to quickly probe many regions on a board and obtain high-accuracy defect classifications in real time.