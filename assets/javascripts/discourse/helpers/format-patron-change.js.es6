import { registerUnbound } from "discourse-common/lib/helpers";
import { htmlSafe } from "@ember/template";

registerUnbound("format-patron-change", function(joined, left) {
  if ((joined === null || joined === undefined) && (left === null || left === undefined)) {
    return htmlSafe('<span class="change-neutral">N/A</span>');
  }

  const j = parseInt(joined, 10) || 0;
  const l = parseInt(left, 10) || 0;

  const joinedHtml = `<span class="change-positive">+${j}</span>`;
  const leftHtml = `<span class="change-negative">-${l}</span>`;

  return htmlSafe(`${joinedHtml} / ${leftHtml}`);
});
