import org.jenkinsci.plugins.workflow.job.*
import org.jenkinsci.plugins.workflow.cps.*

def job = jenkins.model.Jenkins.instance.getItem('Ficha-Caracterizacion-Pipeline-QA')
def newScript = new File('/tmp/Jenkinsfile').text
job.definition = new CpsFlowDefinition(newScript, true)
job.save()
