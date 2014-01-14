function save_options(){
  var user = document.getElementById("user").value;
  var pass = document.getElementById("pass").value;
  localStorage["user"]=user;
  localStorage["pass"]=pass;
}
document.getElementById("user").value = localStorage["user"] || "";
document.getElementById("pass").value = localStorage["pass"] || "";
document.getElementById("submit").onclick = save_options;

