import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import I18n from "I18n";

export default DiscourseRoute.extend({
  beforeModel() {
    if (!this.currentUser) {
      this.replaceWith("login");
    }
  },

  model() {
    return ajax("/patreon-stats.json").catch(error => {
      if (error.jqXHR && error.jqXHR.status === 403) {
        bootbox.alert(I18n.t("patreon_stats.error.not_authorized"));
        this.replaceWith("discovery");
        return { error: true, message: I18n.t("patreon_stats.error.not_authorized") };
      }
      popupAjaxError(error);
      return {
        error: true,
        message: error.jqXHR?.responseJSON?.errors?.[0] || "Unable to fetch statistics"
      };
    });
  }
});
