import { registerRawHelper } from "discourse-common/lib/helpers";

registerRawHelper("month-name", monthName);

export default function monthName(month) {
  const months = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
  ];
  return months[month - 1] || "";
}
