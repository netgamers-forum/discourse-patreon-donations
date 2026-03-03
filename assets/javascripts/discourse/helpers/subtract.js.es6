import { registerUnbound } from "discourse-common/lib/helpers";

registerUnbound("subtract", function(value, subtrahend) {
  const num = parseFloat(value) || 0;
  const sub = parseFloat(subtrahend) || 0;
  return (num - sub).toFixed(4);
});
