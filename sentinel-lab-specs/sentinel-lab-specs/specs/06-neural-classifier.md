# Spec 06 — Neural Classifier (`classifier`)

Read `00-ARCHITECTURE.md` §5.3 (model I/O contract — `activation_snapshot` is mandatory, not optional) before starting. This module can be built in parallel with `knowledge-base` (Phase 5).

## Goal

A trained classifier over standard network-intrusion datasets, served by an inference API that returns predictions **and** the internal activations the faithfulness verifier (Phase 7) needs.

## Allowed paths

`classifier/**`.

## Build

1. Datasets: CICIDS2017 as the primary training set. Optionally add CSE-CIC-IDS2018 for cross-validation and UNSW-NB15 as a generalization test — but get one dataset working end-to-end before adding the others.
2. Feature extraction: clean, encode, normalize; produce a `feature_names.json` manifest listing every feature by stable name (not index) — every other module (`knowledge-base` rules, `telemetry`'s `raw_features`, `fusion`'s attribution step) must reference features by these exact names.
3. Map the dataset's attack-type labels onto the `predicted_class` enum from `00-ARCHITECTURE.md` §5.1. If the dataset has attack categories that don't cleanly map (e.g., a category not in the enum), map it to `ANOMALY_UNKNOWN` rather than inventing a new enum value — a new value is an ADR against the shared schema, not a local decision here.
4. Model: start with a small 1D-CNN (2 conv layers → global pool → dense → softmax) or an MLP if the feature vector is small and low-dimensional — do not start with anything larger. Log every training run (hyperparameters, dataset version, metrics) to `classifier/experiments/<run-id>.json`.
5. Inference server: implement exactly the request/response contract in `00-ARCHITECTURE.md` §5.3, including `activation_snapshot` populated via a forward hook on at least the final dense layer's pre-softmax activations (and ideally one earlier layer too, for a richer attribution signal later). Wire this hook in from the first working version — do not ship a version without it and add it "later."

## Do not

- Do not skip `activation_snapshot` in early iterations "to get something working faster." Every version of this server, from the first, must include it — Phase 7 cannot be retrofitted around a server contract that changes later.
- Do not invent new `predicted_class` values to fit dataset quirks — map to `ANOMALY_UNKNOWN` and note the mapping decision in `classifier/experiments/label-mapping.md`.
- Do not deploy this as a networked service reachable from `demo-app`'s namespace — it lives in its own `classifier` namespace and is called only by `fusion`.

## Acceptance tests

- [ ] `feature_names.json` exists and every downstream reference (rules, telemetry) can be checked against it.
- [ ] Offline evaluation on a held-out test split reports accuracy, precision, recall, F1, and false-positive rate per class — saved to `classifier/experiments/<run-id>-eval.json`.
- [ ] `POST /predict` on the inference server, given a sample feature vector, returns a response matching the exact §5.3 shape, with a non-empty `activation_snapshot`.
- [ ] Calling `/predict` twice with the identical input returns the identical `predicted_class` and `confidence` (determinism check — no unseeded randomness in inference).
