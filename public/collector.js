var startButton = document.querySelector('#start')
var stopButton = document.querySelector('#stop')

startButton.addEventListener('click',async function(){
    alert('Starting the Status Collector');
    try {
        const response = await fetch('/collector/start', {
        method: 'POST'
        });
        
        // Check if the response status is OK (200-299)
        if (!response.ok) {
            throw new Error(`HTTP error! Status: ${response.status}`);
        }
        
        const html = await response.text();
        document.write(html);
    } catch (error) {
        console.error('Request failed:', error);
    }
});

stopButton.addEventListener('click',function(){
    alert('Stopping the Status Collector');
});