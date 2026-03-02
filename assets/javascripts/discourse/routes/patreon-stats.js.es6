import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class PatreonStatsRoute extends DiscourseRoute {
  model() {
    return ajax("/patreon-stats.json");
  }
}
