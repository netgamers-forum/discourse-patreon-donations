import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "patreon-stats-navigation",
  
  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    
    if (!siteSettings.patreon_donations_enabled) {
      return;
    }
    
    withPluginApi("0.8.31", (api) => {
      // Add to hamburger menu
      api.decorateWidget("hamburger-menu:generalLinks", () => {
        return {
          route: "patreon-stats",
          label: "patreon_stats.title",
          className: "patreon-stats-link"
        };
      });
      
      // Add to sidebar (for modern Discourse)
      if (api.addCommunitySectionLink) {
        api.addCommunitySectionLink({
          name: "patreon-stats",
          route: "patreon-stats",
          text: "patreon_stats.title",
          title: "patreon_stats.title"
        });
      }
    });
  }
};
