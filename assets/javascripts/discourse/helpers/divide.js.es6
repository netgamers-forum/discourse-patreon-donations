import { registerUnbound } from "discourse-common/lib/helpers";

registerUnbound("divide", function(value, divisor) {
  const num = parseFloat(value) || 0;
  const div = parseFloat(divisor) || 1;
  return num / div;
});
