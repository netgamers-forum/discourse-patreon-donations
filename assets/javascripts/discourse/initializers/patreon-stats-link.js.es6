import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "patreon-stats-link",
  
  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    
    if (!siteSettings.patreon_enabled) {
      return;
    }

    withPluginApi("0.8.7", api => {
      api.decorateWidget("hamburger-menu:generalLinks", helper => {
        return {
          href: "/patreon-stats",
          label: "patreon_stats.title",
          className: "patreon-stats-link"
        };
      });
    });
  }
};
