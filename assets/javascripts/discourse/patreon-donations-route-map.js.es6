export default {
  resource: "root",
  path: "/",
  map() {
    this.route("patreonStats", { path: "/patreon-stats" });
  }
};
