import { registerRawHelper } from "discourse-common/lib/helpers";

registerRawHelper("multiply", multiply);

export default function multiply(value, multiplier) {
  const result = (parseFloat(value) || 0) * (parseFloat(multiplier) || 0);
  return result.toFixed(2);
}
