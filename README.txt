# PCB Defect Classifier & Streamlit App

This project is an end-to-end pipeline for detecting defects on printed circuit boards (PCBs) using a convolutional neural network and an interactive Streamlit web app.

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


## 1. Project Structure

Expected repo layout:

- `board_scanner.py`  
  Main Streamlit app. Handles:
  - File upload
  - Interactive square crop (via drawable canvas)
  - Preprocessing the crop to 224×224
  - Running inference with the trained model
  - Displaying the predicted defect type and confidence

- `pcb_defect_classifier.keras`  
  Trained Keras model.  
  This is loaded by `board_scanner.py` at runtime.

- `pcb_class_names.pkl`  
  List of class names in the correct order.  
  Used to convert model outputs (indices) into human-readable labels.

- `pcb_class_centroids.npy`
  Numpy array of feature centroids for each class, used for an extra anomaly/“no defect” check.

- `requirements.txt`  
  Python dependencies for Streamlit Cloud and local setup.


## 2. Dependencies

All runtime dependencies are declared in `requirements.txt`:

```
streamlit>=1.30
tensorflow>=2.15,<3.0
numpy>=1.24,<3.0
Pillow>=10.0
matplotlib>=3.8
joblib>=1.3
```

Notes:

- These versions are chosen to be compatible with a typical Linux / Streamlit Cloud environment.
- You do not need `tensorflow-macos` or `tensorflow-metal` on Streamlit Cloud; those are only for local Apple Silicon dev and are managed separately in your local Conda environment.


## 3. How the App Works (High-Level)

1. Model Loading
   - On startup, `board_scanner.py` loads:
     - `pcb_defect_classifier.keras`
     - `pcb_class_names.pkl`
   - The model expects 224×224 RGB images normalized to [0, 1].

2. User Workflow
   - User opens the Streamlit app.
   - Uploads a PCB image (e.g., microscope photo).
   - A drawable canvas is displayed with:
     - The uploaded image as the background.
     - A movable, resizable square crop box.
     - Controls to zoom in/out the displayed image.
   - The user positions and resizes the square until it covers the trace region of interest.
   - User clicks Submit.
   - The app:
     - Extracts the selected region.
     - Resizes it to 224×224.
     - Normalizes the pixels.
     - Runs the patch through the model.

3. Prediction & Output
   - The app computes class probabilities from the softmax output.
   - It selects the top predicted class and shows:
     - The predicted defect label.
     - The associated probability (e.g., “spur – 97.3%”).
   - If all probabilities are below a configurable threshold, the app displays:
     - “No defect detected with high confidence.”
   - It can also flag “anomalous / unknown pattern” when the feature vector is far from all class centroids.


## 4. Running the App Locally

These steps assume you’re using Conda and Apple Silicon (M-series), but the general flow is similar on other platforms.

1. Clone / copy the repo to your machine and ensure these files are present in the project folder:
   - `board_scanner.py`
   - `requirements.txt`
   - `pcb_defect_classifier.keras`
   - `pcb_class_names.pkl`
   - `pcb_class_centroids.npy`
   - `README.txt`

2. **Create and activate a Conda environment** (example):

   ```bash
   conda create -n pcbapp python=3.10
   conda activate pcbapp
   ```

3. **Install dependencies** from `requirements.txt`:

   ```bash
   pip install -r requirements.txt
   ```

   > On Apple Silicon you may additionally install `tensorflow-macos` / `tensorflow-metal` if running training locally, but this isn’t required just to run the app with a pre-trained model.

4. **Run the Streamlit app**:

   ```bash
   streamlit run board_scanner.py
   ```

5. **Open the app**
   - Streamlit will print a local URL, typically:
     - `http://localhost:8501`
   - Open this URL in your browser to use the app.


## 5. Model Training (Background)

Model training is **not** required for using the deployed app, but for reproducibility:

- Training is done in a separate **Google Colab** notebook:
  - Builds a dataset of cropped defect patches from the Kaggle PCB dataset.
  - Runs a custom CNN with BatchNorm, data augmentation, and a learning rate schedule.
  - Evaluates on val/test splits.
  - Saves:
    - `pcb_defect_classifier.keras`
    - `pcb_class_names.pkl`
    - `pcb_class_centroids.npy`

- After training in Colab:
  - Download these artifacts.


## 6. Usage Tips & Limitations

- The model is trained on patches centered on defects. For best results, the crop in the app should:
  - Keep the defect near the center.
  - Include enough local context without being too zoomed out.

- If the uploaded image is extremely high-resolution:
  - It’s typically better to zoom out slightly and then let the app resize to 224×224, rather than cropping a tiny region with extremely fine detail.

- This model recognizes only the six defect types it was trained on.
  - Other kinds of damage or artifacts may be flagged as “no defect detected” or misclassified.



## 7. Summary

This project delivers an end-to-end pipeline for PCB defect detection: a CNN trained on Kaggle PCB defect patches, wrapped in an interactive Streamlit app where users can upload microscope images, crop regions of interest, and receive fast, explainable predictions across six defect types.

Current limitations:

- Manual patch selection only – The app can’t yet scan whole boards automatically; the user must draw a square crop around each region of interest.
- Limited defect vocabulary – The model only knows the six Kaggle defect classes and may misbehave on unseen defect types, unusual PCB layouts, or very different imaging conditions.
- Single-patch, single-defect focus – The system classifies one selected patch at a time; it does not localize, count, or characterize multiple defects across an entire PCB image.

Going forward, natural next steps include adding full-board scanning (sliding-window or detector-style models), expanding the defect taxonomy with additional labeled data, and hardening the pipeline against real-world variation in lighting, zoom, and board design. Together, these extensions would turn the current proof-of-concept into a more general, production-ready PCB inspection assistant that could be deployed at my company.
