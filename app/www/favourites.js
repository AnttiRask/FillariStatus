// Favourite station IDs: localStorage <-> Shiny input `favourites`.
// Storage can be unavailable (private windows, blocked site data), so every
// access is wrapped; favourites then last for the current page only.
(function () {
  var KEY = "fillaristatus.favourites";

  function read() {
    try {
      var v = JSON.parse(localStorage.getItem(KEY));
      return Array.isArray(v) ? v : [];
    } catch (e) {
      return [];
    }
  }

  function write(list) {
    try {
      localStorage.setItem(KEY, JSON.stringify(list));
    } catch (e) {}
  }

  var current = read();

  function publish() {
    Shiny.setInputValue("favourites", current, { priority: "event" });
  }

  $(document).on("shiny:connected", publish);

  $(document).on("click", ".fs-fav", function () {
    var id = this.getAttribute("data-station-id");
    var i = current.indexOf(id);
    if (i === -1) {
      current.push(id);
    } else {
      current.splice(i, 1);
    }
    write(current);
    publish();
  });
})();
