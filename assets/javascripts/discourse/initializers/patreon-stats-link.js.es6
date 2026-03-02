import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "patreon-stats-link",
  
  initialize() {
    withPluginApi("0.8.31", api => {
      api.decorateWidget("hamburger-menu:generalLinks", helper => {
        if (!helper.widget.siteSettings.patreon_enabled) {
          return;
        }
        
        return {
          route: "patreon-stats",
          label: "patreon_stats.title",
          className: "patreon-stats-link"
        };
      });
    });
  }
};
