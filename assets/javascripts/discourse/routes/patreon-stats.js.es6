import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
export default DiscourseRoute.extend({
  beforeModel() {
    if (!this.currentUser) {
      this.replaceWith("login");
    }
  },

  model() {
    return ajax("/patreon-stats.json").catch(error => {
      if (error.jqXHR && error.jqXHR.status === 403) {
        this.replaceWith("discovery");
        return { error: true, message: "You are not authorized to view this page." };
      }
      popupAjaxError(error);
      return {
        error: true,
        message: error.jqXHR?.responseJSON?.errors?.[0] || "Unable to fetch statistics"
      };
    });
  }
});
