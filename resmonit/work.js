//alert(localStorage["user"]);
var storage = {};

accounts = [];

function updateAccounts(){
    $.getJSON("http://localhost:7379/KEYS/riag:account:*", function(data){
        $.each(data.KEYS,function(i,dat){
            accounts.push(dat.split(":")[2])
        });
        checkName()
    });
}
updateAccounts();
count = 0
function checkName(){
    var n_count = document.getElementsByClassName('sitetable').length
    if(count != n_count){
        $(".thing .entry").each(function(i, elem){
            if(accounts.indexOf($(elem).find(".author").text())!=-1){
                $(elem).attr("style","background-color: teal !important");
            }
        });
        count = n_count;
    }
}
setInterval(checkName, 1000)

