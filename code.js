exports.handler = async (event, context) => {
  // Get the email address of the caller using the AI function
  const email = await context.ctm.ask("Extract the email address from the given message");
  console.log("we got an email:", email)
  
  if (email?.length) {
    // Update the activity record with the email address
    await context.ctm.update({email: email});
  }
};
