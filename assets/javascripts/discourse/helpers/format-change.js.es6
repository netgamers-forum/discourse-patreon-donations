import { registerUnbound } from "discourse-common/lib/helpers";
import { htmlSafe } from "@ember/template";

registerUnbound("format-change", function(value) {
  if (value === null || value === undefined) {
    return htmlSafe('<span class="change-neutral">N/A</span>');
  }
  
  const numValue = parseFloat(value);
  if (isNaN(numValue)) {
    return htmlSafe('<span class="change-neutral">N/A</span>');
  }
  
  const absValue = Math.abs(numValue).toFixed(2);
  
  if (numValue > 0) {
    return htmlSafe(`<span class="change-positive">+$${absValue}</span>`);
  } else if (numValue < 0) {
    return htmlSafe(`<span class="change-negative">-$${absValue}</span>`);
  } else {
    return htmlSafe('<span class="change-neutral">$0.00</span>');
  }
});
