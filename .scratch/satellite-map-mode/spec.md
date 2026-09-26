# Satellite map mode

## Goal

Experiment with satellite imagery in the campus map and judge whether it makes
campus places easier to recognize without making navigation harder.

## Agreed behavior

- Provide a Map/Satellite toggle; Map remains the default.
- Use Esri World Imagery for satellite tiles and show its required attribution.
- Remember the selected style between app launches.
- Keep campus boundaries, routes, markers, and labels unchanged for the first
  pass.
- If satellite tiles fail, keep Satellite selected, show a clear error, and
  provide an easy way to switch back to Map.

## Scope

Implement this as an app-quality experiment on `feat/satellite-map-mode`.
