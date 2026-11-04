// Leaflet 1.3 (bundled with the R leaflet package) sometimes keeps a tile from a
// lower zoom level after a zoom has finished: the retained parent is only dropped
// when every new tile has finished fading in, and that check can miss. The labels
// layer is transparent, so the stretched old tile shows through as a huge blurry
// label. After the last tile of a layer has loaded, prune explicitly.
document.addEventListener("DOMContentLoaded", function () {
  if (!window.L || !L.GridLayer) return;
  var tileReady = L.GridLayer.prototype._tileReady;
  L.GridLayer.prototype._tileReady = function () {
    tileReady.apply(this, arguments);
    var layer = this;
    if (layer._noTilesToLoad && layer._noTilesToLoad()) {
      setTimeout(function () {
        if (layer._map) layer._pruneTiles();
      }, 400);
    }
  };
});
