import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default DiscourseRoute.extend({
  model() {
    return ajax("/patreon-stats.json").catch(error => {
      popupAjaxError(error);
      return {
        error: true,
        message: error.jqXHR?.responseJSON?.errors?.[0] || "Unable to fetch statistics"
      };
    });
  }
});
